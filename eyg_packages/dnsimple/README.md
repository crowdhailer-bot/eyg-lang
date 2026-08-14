# dnsimple

An example company context. Start an overlay session with it and the agent can
read the domains and DNS records of a DNSimple account.

```
https://eyg.run/overlay?package=dnsimple
```

The module is a record with a `readme`, which is what makes it a context. The
readme is the agents instructions, `readme.eyg` is the whole of it.

## Public API

| Helper                      | What it does                                                             |
| --------------------------- | ------------------------------------------------------------------------ |
| `whoami({})`                | `Result(Integer, String)`, the account id every other call needs.        |
| `domains(account)`          | `Result(List({id, name}), String)`, every domain in the account.         |
| `records({account, zone})`  | `Result(List({id, name, type, content, ttl}), String)` for one zone.     |

Every call performs the `DNSimple` effect. The platform attaches the token, in
the browser through spotless, so nothing in this package handles credentials.
The first call of a session asks the user to connect.
