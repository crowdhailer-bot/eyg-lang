//// Shared artifacts, bundles of files created in Overlay.
////
//// Overlay shares a bundle once a person chooses to, until then artifacts stay
//// in the browser session.

import eyg/hub/artifact as rules
import eyg/hub/schema
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import hub/artifacts/data
import hub/server/context.{type Context}
import hub/web/utils
import pog
import wisp

/// Base64 content is a third larger than the files it encodes.
const max_upload = 3_000_000

/// Shares allowed from one address in ten minutes.
const max_shares = 30

pub fn share(
  request: Request(wisp.Connection),
  context: Context,
) -> Response(wisp.Body) {
  let request = wisp.set_max_body_size(request, max_upload)
  case utils.content_type(request) {
    Ok("application/json") -> {
      use body <- wisp.require_string_body(request)
      case json.parse(body, schema.artifact_decoder()) {
        Ok(#(name, files)) ->
          case rules.validate(name, files) {
            Ok(Nil) -> insert(name, files, utils.client_ip(request), context)
            Error(reason) -> utils.api_reason(422, reason)
          }
        Error(_) -> utils.api_reason(400, "Expected an artifact name and files")
      }
    }
    _ -> wisp.unsupported_media_type(accept: ["application/json"])
  }
}

fn insert(name, files, ip, context: Context) {
  use count <- utils.db_result(pog.execute(data.count_by_ip(ip), context.db))
  case count.rows {
    [count] if count >= max_shares ->
      utils.api_reason(429, "Too many artifacts shared, try again later")
    _ -> {
      use returned <- utils.db_result(pog.execute(
        data.insert(name, files, ip),
        context.db,
      ))
      case returned.rows {
        [id] ->
          wisp.json_response(
            json.to_string(schema.shared_artifact_encode(id)),
            201,
          )
          |> wisp.set_header("location", "/artifact/" <> id)
        _ -> wisp.internal_server_error()
      }
    }
  }
}

/// The bundle as JSON, so it can be opened and changed again.
pub fn get(id: String, context: Context) -> Response(wisp.Body) {
  use artifact <- find(id, context)
  use returned <- utils.db_result(pog.execute(data.files(id), context.db))
  wisp.json_response(
    json.to_string(schema.artifact_encode(artifact.name, returned.rows)),
    200,
  )
}

fn find(id, context: Context, then) {
  case rules.valid_id(id) {
    False -> wisp.not_found()
    True ->
      case pog.execute(data.get(id), context.db) {
        Ok(pog.Returned(rows: [artifact], ..)) -> then(artifact)
        Ok(_) -> wisp.not_found()
        Error(_) -> wisp.response(503)
      }
  }
}
