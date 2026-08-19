# TODO

## inspiration: `mnesia` error propagation

- process A makes a `call` on process B
- process B is unable to perform the action, and so throws an error
  - BUG: process A swallows error and continues
    - process B relied on the error propagating so it could reach a retry handler
  - FIX: process A propagates error, allowing action to be retried as process B intended

### questions

- does process B need/often interact with a resource on behalf of process A?

