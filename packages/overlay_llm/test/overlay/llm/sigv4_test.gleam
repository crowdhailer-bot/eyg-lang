import gleam/http
import gleam/http/request
import gleam/list
import gleam/option.{None}
import gleam/time/timestamp
import overlay/llm/sigv4

// The get-vanilla example from the AWS SigV4 test suite.
pub fn get_vanilla_test() {
  let assert Ok(time) = timestamp.parse_rfc3339("2015-08-30T12:36:00Z")
  let request =
    request.new()
    |> request.set_method(http.Get)
    |> request.set_host("example.amazonaws.com")
    |> request.set_path("/")
    |> request.set_body(<<>>)
  let credentials =
    sigv4.Credentials(
      "AKIDEXAMPLE",
      "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
      None,
    )
  let signed = sigv4.sign(request, credentials, "us-east-1", "service", time)
  assert list.key_find(signed.headers, "authorization")
    == Ok(
      "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, SignedHeaders=host;x-amz-date, Signature=5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31",
    )
  assert list.key_find(signed.headers, "x-amz-date") == Ok("20150830T123600Z")
}

pub fn encode_test() {
  assert sigv4.encode("anthropic.claude:0") == "anthropic.claude%3A0"
  assert sigv4.encode("a%3A") == "a%253A"
}
