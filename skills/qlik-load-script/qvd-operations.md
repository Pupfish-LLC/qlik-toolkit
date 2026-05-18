# QVD Operations

STORE syntax, optimized vs standard read modes, map-building from resident, and binary load rules.

---

## STORE Syntax

```qlik
STORE * FROM [TableName] INTO [lib://Connection/path/file.qvd] (qvd);
STORE Field1, Field2 FROM [TableName] INTO [lib://Connection/file.qvd] (qvd);
```

One table per STORE.

---

## QVD Read Modes

QVD files support two read modes. Optimized read is ~10x faster than standard QVD read and ~100x faster than reading from a database. Standard read is still ~10x faster than database.

### What preserves optimized read

- `LOAD *` (all fields, no transforms)
- Field subsetting (loading specific fields by name)
- Field renaming with `AS` (e.g., `source_col AS [New.Name]`)
- `LOAD DISTINCT` (note: DISTINCT processing occurs after the optimized read phase completes, so the read itself remains fast)
- `CONCATENATE` load
- One-parameter `EXISTS(field)` / `NOT EXISTS(field)` (single field name, no second argument)
- Preceding LOAD above the QVD LOAD (the inner QVD read remains optimized; the preceding load processes in-memory after the fast read)

### What forces standard read

- Transformations or functions on fields (e.g., `Upper(name)`, `Date#(date_field)`)
- Derived/calculated fields (e.g., `field1 & '-' & field2 AS CompositeKey`)
- Two-parameter `EXISTS(field, expression)` (the expression form)
- WHERE clauses other than one-parameter EXISTS (e.g., `WHERE amount > 0`)
- `Map...Using` applied to fields being loaded
- `MAPPING LOAD` from QVD

```qlik
// Optimized -- field rename, subset, one-parameter NOT EXISTS:
LOAD customer_id AS [Customer.Key], name AS [Customer.Name]
FROM [lib://QVDs/Customers.qvd] (qvd)
WHERE NOT EXISTS([Order.Key]);

// Standard -- two-parameter EXISTS or transforms force unpack:
LOAD Upper(name) AS [Customer.Name]
FROM [lib://QVDs/Customers.qvd] (qvd)
WHERE NOT EXISTS([Existing.Key], [Order.Key]);
```

---

## Load Once, Create Multiple Maps

Never read the same QVD from disk multiple times. Load to temp, create maps from resident, drop temp.

```qlik
[_Temp]: LOAD key, field_a, field_b FROM [file.qvd] (qvd);
Map_A: MAPPING LOAD key, field_a RESIDENT [_Temp];
Map_B: MAPPING LOAD key, field_b RESIDENT [_Temp];
DROP TABLE [_Temp];
```

---

## Binary Load

`binary [app_id_or_path];` must be the FIRST statement in the script (before SET). Loads data tables and section access data only (no sheets, variables, master items). Only ONE binary statement per script.
