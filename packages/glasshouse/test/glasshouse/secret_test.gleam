import eyg/interpreter/value as v
import glasshouse/helpers.{sha256}
import glasshouse/lock
import glasshouse/recorder
import glasshouse/secret.{Secret}
import gleam/dict
import gleam/json
import gleam/string

const token = Secret("github", "ghp_s3cr3t")

pub fn redact_replaces_in_nested_values_test() {
  let request =
    v.Record(
      dict.from_list([
        #("headers", v.LinkedList([v.String("Bearer ghp_s3cr3t")])),
        #("body", v.Binary(<<"token=ghp_s3cr3t">>)),
      ]),
    )
  let redacted = secret.redact(request, [token])
  let expected =
    v.Record(
      dict.from_list([
        #("headers", v.LinkedList([v.String("Bearer ⟦secret:github⟧")])),
        #("body", v.Binary(<<"token=⟦secret:github⟧":utf8>>)),
      ]),
    )
  assert redacted == expected
  assert secret.restore(redacted, [token]) == request
}

pub fn non_utf8_binaries_are_unchanged_test() {
  let bytes = v.Binary(<<255, 0, 255>>)
  assert secret.redact(bytes, [token]) == bytes
}

pub fn longer_secrets_are_replaced_first_test() {
  let short = Secret("short", "abc")
  let long = Secret("long", "abcdef")
  assert secret.redact(v.String("abcdef abc"), [short, long])
    == v.String("⟦secret:long⟧ ⟦secret:short⟧")
}

pub fn empty_secrets_are_ignored_test() {
  assert secret.redact(v.String("text"), [Secret("empty", "")])
    == v.String("text")
}

pub fn dummy_replays_redact_to_the_same_placeholder_test() {
  let real = secret.redact(v.String("Bearer ghp_s3cr3t"), [token])
  let dummy = secret.dummy("github")
  let replayed = secret.redact(v.String("Bearer " <> dummy.value), [dummy])
  assert real == replayed
}

pub fn reveals_test() {
  assert secret.reveals("x ghp_s3cr3t y", [token])
  assert !secret.reveals("nothing here", [token])
}

pub fn credential_variables_test() {
  assert secret.is_credential_variable("GITHUB_TOKEN")
  assert secret.is_credential_variable("openai_api_key")
  assert secret.is_credential_variable("DB_PASSWORD")
  assert !secret.is_credential_variable("HOME")
  assert !secret.is_credential_variable("PATH")
}

pub fn locks_keep_a_hash_of_each_secret_test() {
  let recorder =
    recorder.new(sha256)
    |> recorder.add_secret(secret.Secret("github", "ghp_real_token"))
  let lock = recorder.lock_secrets(recorder, lock.empty())
  assert dict.get(lock.secrets, "github")
    == Ok(recorder.digest(sha256, "ghp_real_token"))
  // The value itself is never in the lock.
  let encoded = json.to_string(lock.encode(lock))
  assert !string.contains(encoded, "ghp_real_token")
  assert json.parse(encoded, lock.decoder()) == Ok(lock)
}

pub fn locks_without_secrets_still_decode_test() {
  let assert Ok(lock) =
    json.parse(
      "{\"files\": {}, \"packages\": {}, \"versions\": []}",
      lock.decoder(),
    )
  assert lock == lock.empty()
}
