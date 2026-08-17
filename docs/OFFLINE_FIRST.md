# BALI STOCK offline-first

BALI STOCK now treats the local SQLite database as the first write target for warehouse operations.

Core behavior:
- warehouse screens open from local SQLite without network;
- delivery, stocktake, write-off and transfer are committed locally first;
- the same operation is stored in `sync_outbox` with a unique `client_action_id`;
- queued actions are sent through `bali-stock-sync-api` when connectivity is available;
- the server deduplicates `client_action_id` so retries do not duplicate stock movement;
- after the queue becomes empty, the client pulls the authoritative shared snapshot;
- if the process restarts, the outbox remains in SQLite and resumes later;
- the operation PIN is not persisted; if the app was fully terminated while actions are pending, synchronization resumes after the next protected-session PIN entry.

Historical corrections remain server-connected because they need the canonical server operation UUID.
