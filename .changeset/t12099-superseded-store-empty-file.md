---
id: t12099-superseded-store-empty-file
tasks: [T12099]
kind: fix
summary: doctor superseded-store reports a 0-byte legacy DB (brain.db) as provably empty instead of "an unknown number of rows"
---

`cleo doctor superseded-store` treated a 0-byte superseded store file the same as a corrupt one: `rowsInSuperseded: null`, `safeToArchive: false`, and a reason telling the user to "reconcile the contents first" of a file that holds nothing by definition. A 0-byte file now bypasses `countRows`, reports 0 rows, and gets the normal safe-to-archive verdict; corrupt nonzero files keep the conservative `null` path.
