//// A DNSimple account served from memory, so evals can run programs that call
//// the DNSimple API and check both what they return and what they changed.
//// Only the endpoints the DNSimple context uses are implemented.

import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/http
import gleam/http/response.{Response}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import jev_playground/run
import ogre/operation
import touch_grass/decode_json
import touch_grass/http as tg_http

/// The DNSimple context in `eyg_packages/dnsimple`, as shared to the hub.
pub const context_id = "baguqeeracc7b5hsiftxjtbza4uc7o4pw5to64iyezckifumrgn22x4aibo5q"

pub const context_path = "../../eyg_packages/dnsimple/index.eyg"

pub type Record {
  Record(
    id: Int,
    name: String,
    type_: String,
    content: String,
    ttl: Int,
    priority: Option(Int),
  )
}

pub type Domain {
  Domain(
    id: Int,
    name: String,
    registered: Bool,
    auto_renew: Bool,
    expires_on: Option(String),
    records: List(Record),
  )
}

pub type Account {
  Account(
    id: Int,
    email: String,
    plan: String,
    domains: List(Domain),
    /// Names that can be registered, every other name is taken.
    available: List(String),
    name_servers: List(String),
    next_id: Int,
  )
}

fn record(id, name, type_, content) {
  Record(id:, name:, type_:, content:, ttl: 3600, priority: None)
}

fn mx(id, content, priority) {
  Record(
    id:,
    name: "",
    type_: "MX",
    content:,
    ttl: 3600,
    priority: Some(priority),
  )
}

pub fn fixture() -> Account {
  Account(
    id: 1385,
    email: "ada@lovelace.dev",
    plan: "teams-v1-monthly",
    domains: [
      Domain(
        id: 1,
        name: "lovelace.dev",
        registered: True,
        auto_renew: True,
        expires_on: Some("2027-03-15"),
        records: [
          record(101, "", "A", "93.184.215.14"),
          record(102, "", "A", "93.184.215.15"),
          record(103, "www", "CNAME", "lovelace.dev"),
          record(104, "api", "A", "198.51.100.1"),
          mx(105, "mail.lovelace.dev", 10),
          record(106, "old", "TXT", "legacy-verification=4f2a"),
          record(107, "", "TXT", "v=spf1 include:_spf.lovelace.dev ~all"),
        ],
      ),
      Domain(
        id: 2,
        name: "analytical.engineering",
        registered: True,
        auto_renew: False,
        expires_on: Some("2026-11-30"),
        records: [
          record(201, "", "A", "203.0.113.10"),
          mx(202, "aspmx.l.google.com", 1),
          mx(203, "alt1.aspmx.l.google.com", 5),
          record(204, "blog", "CNAME", "hosting.example.net"),
        ],
      ),
      Domain(
        id: 3,
        name: "notes.garden",
        registered: True,
        auto_renew: False,
        expires_on: Some("2028-01-02"),
        records: [record(301, "", "A", "192.0.2.44")],
      ),
      Domain(
        id: 4,
        name: "babbage.org",
        registered: False,
        auto_renew: False,
        expires_on: None,
        records: [
          record(401, "", "A", "192.0.2.80"),
          record(402, "docs", "CNAME", "babbage.org"),
        ],
      ),
    ],
    available: ["jev-rocks.com", "ada-codes.dev"],
    name_servers: [
      "ns1.dnsimple.com",
      "ns2.dnsimple-edge.net",
      "ns3.dnsimple.com",
      "ns4.dnsimple-edge.org",
    ],
    next_id: 1000,
  )
}

pub fn find_domain(account: Account, name) -> Result(Domain, Nil) {
  list.find(account.domains, fn(domain) { domain.name == name })
}

/// Handle the effects a program using the DNSimple context performs.
pub fn handle(
  account: Account,
  label: String,
  lift: run.Value,
) -> Result(#(run.Value, Account), String) {
  case label {
    "DNSimple" -> {
      use operation <- result.try(
        tg_http.operation_to_gleam(lift)
        |> result.replace_error(
          "DNSimple was given a value that is not an operation",
        ),
      )
      let #(status, body, account) = serve(account, operation)
      let response =
        Response(
          status:,
          headers: [#("content-type", "application/json")],
          body:,
        )
      Ok(#(v.ok(tg_http.response_to_eyg(response)), account))
    }
    "DecodeJSON" ->
      case cast.as_binary(lift) {
        Ok(raw) -> Ok(#(decode_json.sync(raw), account))
        Error(_) -> Error("DecodeJSON was given a value that is not binary")
      }
    "Abort" ->
      case lift {
        v.String(reason) -> Error("the program aborted: " <> reason)
        _ -> Error("the program aborted")
      }
    _ -> Error("the effect " <> label <> " is not available in this eval")
  }
}

/// Answer a DNSimple API request made over HTTP, for a page to call the account.
pub fn respond(
  account: Account,
  method: String,
  path: String,
  body: BitArray,
) -> #(Int, BitArray, Account) {
  let method = http.parse_method(method) |> result.unwrap(http.Get)
  serve(
    account,
    operation.Operation(method:, path:, query: None, headers: [], body:),
  )
}

fn serve(
  account: Account,
  operation: operation.Operation(BitArray),
) -> #(Int, BitArray, Account) {
  let operation.Operation(method:, path:, body:, ..) = operation
  let segments = case string.split(path, "/") {
    ["", ..segments] -> segments
    segments -> segments
  }
  let own = int.to_string(account.id)
  case method, segments {
    http.Get, ["v2", "whoami"] -> ok(data(whoami(account)), account)
    http.Get, ["v2", id, "domains"] if id == own ->
      ok(
        paginated(
          json.array(account.domains, domain_json),
          list.length(account.domains),
        ),
        account,
      )
    http.Get, ["v2", _, "domains", name] ->
      case find_domain(account, name) {
        Ok(domain) -> ok(data(domain_json(domain)), account)
        Error(Nil) -> missing("Domain", name, account)
      }
    http.Get, ["v2", _, "zones", zone, "records"] ->
      case find_domain(account, zone) {
        Ok(domain) ->
          ok(
            paginated(
              json.array(domain.records, record_json(domain, _)),
              list.length(domain.records),
            ),
            account,
          )
        Error(Nil) -> missing("Zone", zone, account)
      }
    http.Post, ["v2", _, "zones", zone, "records"] ->
      case find_domain(account, zone), decode_record(body) {
        Ok(domain), Ok(#(name, type_, content, ttl)) -> {
          let created =
            Record(
              id: account.next_id,
              name:,
              type_:,
              content:,
              ttl:,
              priority: None,
            )
          let domain =
            Domain(..domain, records: list.append(domain.records, [created]))
          let account =
            Account(..replace(account, domain), next_id: account.next_id + 1)
          #(201, encode(data(record_json(domain, created))), account)
        }
        Error(Nil), _ -> missing("Zone", zone, account)
        _, Error(reason) -> #(400, message(reason), account)
      }
    http.Patch, ["v2", _, "zones", zone, "records", id] ->
      case find_domain(account, zone), int.parse(id), decode_content(body) {
        Ok(domain), Ok(id), Ok(content) ->
          case list.find(domain.records, fn(r) { r.id == id }) {
            Ok(found) -> {
              let changed = Record(..found, content:)
              let records =
                list.map(domain.records, fn(r) {
                  case r.id == id {
                    True -> changed
                    False -> r
                  }
                })
              let domain = Domain(..domain, records:)
              #(
                200,
                encode(data(record_json(domain, changed))),
                replace(account, domain),
              )
            }
            Error(Nil) -> not_found(account)
          }
        _, _, Error(reason) -> #(400, message(reason), account)
        _, _, _ -> not_found(account)
      }
    http.Delete, ["v2", _, "zones", zone, "records", id] ->
      case find_domain(account, zone), int.parse(id) {
        Ok(domain), Ok(id) -> {
          let records = list.filter(domain.records, fn(r) { r.id != id })
          case list.length(records) == list.length(domain.records) {
            True -> not_found(account)
            False -> #(204, <<>>, replace(account, Domain(..domain, records:)))
          }
        }
        _, _ -> not_found(account)
      }
    http.Get, ["v2", _, "registrar", "domains", name, "check"] ->
      ok(
        data(
          json.object([
            #("domain", json.string(name)),
            #("available", json.bool(list.contains(account.available, name))),
            #("premium", json.bool(False)),
          ]),
        ),
        account,
      )
    http.Get, ["v2", _, "registrar", "domains", name, "delegation"] ->
      case find_domain(account, name) {
        Ok(Domain(registered: True, ..)) ->
          ok(data(json.array(account.name_servers, json.string)), account)
        Ok(_) -> #(
          400,
          message("The domain is not registered with DNSimple"),
          account,
        )
        Error(Nil) -> missing("Domain", name, account)
      }
    http.Put, ["v2", _, "registrar", "domains", name, "auto_renewal"] ->
      set_auto_renew(account, name, True)
    http.Delete, ["v2", _, "registrar", "domains", name, "auto_renewal"] ->
      set_auto_renew(account, name, False)
    _, _ -> not_found(account)
  }
}

fn set_auto_renew(account, name, auto_renew) {
  case find_domain(account, name) {
    Ok(Domain(registered: True, ..) as domain) -> #(
      204,
      <<>>,
      replace(account, Domain(..domain, auto_renew:)),
    )
    Ok(_) -> #(
      400,
      message("The domain is not registered with DNSimple"),
      account,
    )
    Error(Nil) -> missing("Domain", name, account)
  }
}

fn replace(account: Account, domain: Domain) -> Account {
  let domains =
    list.map(account.domains, fn(d) {
      case d.name == domain.name {
        True -> domain
        False -> d
      }
    })
  Account(..account, domains:)
}

fn ok(body, account) {
  #(200, encode(body), account)
}

fn not_found(account) {
  #(404, message("Not found"), account)
}

// The messages the API gives for a zone or domain that is not in the account.
fn missing(kind, name, account) {
  #(404, message(kind <> " `" <> name <> "` not found"), account)
}

fn message(text) {
  encode(json.object([#("message", json.string(text))]))
}

fn encode(body: json.Json) -> BitArray {
  bit_array.from_string(json.to_string(body))
}

fn data(value) {
  json.object([#("data", value)])
}

// Lists come with pagination beside the data, everything fits on one page.
fn paginated(items, count) {
  json.object([
    #("data", items),
    #(
      "pagination",
      json.object([
        #("current_page", json.int(1)),
        #("per_page", json.int(100)),
        #("total_entries", json.int(count)),
        #("total_pages", json.int(1)),
      ]),
    ),
  ])
}

fn whoami(account: Account) {
  json.object([
    #("user", json.null()),
    #(
      "account",
      json.object([
        #("id", json.int(account.id)),
        #("email", json.string(account.email)),
        #("plan_identifier", json.string(account.plan)),
      ]),
    ),
  ])
}

fn domain_json(domain: Domain) {
  json.object([
    #("id", json.int(domain.id)),
    #("name", json.string(domain.name)),
    #("unicode_name", json.string(domain.name)),
    #(
      "state",
      json.string(case domain.registered {
        True -> "registered"
        False -> "hosted"
      }),
    ),
    #("auto_renew", json.bool(domain.auto_renew)),
    #("private_whois", json.bool(False)),
    #("expires_on", json.nullable(domain.expires_on, json.string)),
  ])
}

fn record_json(domain: Domain, record: Record) {
  json.object([
    #("id", json.int(record.id)),
    #("zone_id", json.string(domain.name)),
    #("name", json.string(record.name)),
    #("content", json.string(record.content)),
    #("ttl", json.int(record.ttl)),
    #("priority", json.nullable(record.priority, json.int)),
    #("type", json.string(record.type_)),
    #("system_record", json.bool(False)),
  ])
}

fn decode_record(body) {
  let decoder = {
    use name <- decode.field("name", decode.string)
    use type_ <- decode.field("type", decode.string)
    use content <- decode.field("content", decode.string)
    use ttl <- decode.optional_field("ttl", 3600, decode.int)
    decode.success(#(name, type_, content, ttl))
  }
  json.parse_bits(body, decoder)
  |> result.replace_error("the record could not be read")
}

fn decode_content(body) {
  json.parse_bits(body, decode.field("content", decode.string, decode.success))
  |> result.replace_error("the change could not be read")
}

// Values as the context returns them, for checkers to compare with.

pub fn record_value(record: Record) -> run.Value {
  v.Record(
    dict.from_list([
      #("id", v.Integer(record.id)),
      #("name", v.String(record.name)),
      #("type", v.String(record.type_)),
      #("content", v.String(record.content)),
      #("ttl", v.Integer(record.ttl)),
      #("priority", v.Integer(option.unwrap(record.priority, 0))),
    ]),
  )
}

pub fn strings(items: List(String)) -> run.Value {
  v.LinkedList(list.map(items, v.String))
}

pub fn domain_value(domain: Domain) -> run.Value {
  v.Record(
    dict.from_list([
      #("name", v.String(domain.name)),
      #(
        "state",
        v.String(case domain.registered {
          True -> "registered"
          False -> "hosted"
        }),
      ),
      #("auto_renew", v.bool(domain.auto_renew)),
      #("expires_on", v.String(option.unwrap(domain.expires_on, ""))),
    ]),
  )
}
