open Crowbar
open Common

(* XXX(dinosaure): we did not generate UTF-8 valid string - we refer only on RFC 822. *)

let local_word =
  map [ dynamic_bind (range ~min:1 78) (string_from_alphabet atext) ]
    (fun str -> match Mrmime.Mailbox.Local.word str with
       | Ok str -> str
       | Error _ -> bad_test ())

let local = list1 local_word

let domain_atom = map [ dynamic_bind (range ~min:1 78) (string_from_alphabet dtext) ]
    (fun input -> match Mrmime.Mailbox.Domain.atom input with
       | Ok v -> v
       | Error _ -> bad_test ())

let domain = map [ list1 domain_atom ] (fun lst -> `Domain (List.map (fun (`Atom x) -> x) lst))

(* XXX(dinosaure): we did not include [`Literal] domain because [Rfc822.domain]
   excludes it according to RFC 5321 (see [Rfc822.domain]). *)

let message_id =
  map [ local; domain ]
    (fun local domain -> (local, domain))

module BBuffer = Buffer

let emitter_of_buffer buf =
  let open Mrmime.Encoder in

  let write a = function
    | { IOVec.buffer= Buffer.String x; off; len; } ->
      BBuffer.add_substring buf x off len; a + len
    | { IOVec.buffer= Buffer.Bytes x; off; len; } ->
      BBuffer.add_subbytes buf x off len; a + len
    | { IOVec.buffer= Buffer.Bigstring x; off; len; } ->
      BBuffer.add_string buf (Bigstringaf.substring x ~off ~len); a + len in
  List.fold_left write 0

let () =
  let open Mrmime in

  Crowbar.add_test ~name:"message_id" [ message_id ] @@ fun message_id ->

  let buffer = Buffer.create 0x100 in
  let encoder = Encoder.create ~margin:78 ~new_line:"\r\n" 0x100 ~emitter:(emitter_of_buffer buffer) in
  let encoder = Encoder.keval Encoder.flush encoder Encoder.[ !!MessageID.Encoder.message_id; new_line; new_line ] message_id in

  check_eq ~pp:Fmt.bool ~eq:(=) (Encoder.is_empty encoder) true ;

  let result = Buffer.contents buffer in

  match Angstrom.parse_string Angstrom.(Rfc822.msg_id ~address_literal:(fail "Invalid domain") <* Rfc822.crlf <* Rfc822.crlf) result with
  | Ok message_id' ->
    check_eq ~pp:MessageID.pp ~eq:MessageID.equal message_id message_id'
  | Error err ->
    Fmt.epr "message-id: @[<hov>%a@]\n%!" MessageID.pp message_id ;
    Fmt.epr "output: @[<hov>%a@]\n%!" (Hxd_string.pp Hxd.O.default) result ;
    failf "%a can not be parsed: %s" MessageID.pp message_id err
