# Domain Modeling Patterns

Reference file for the domain-review agent. Read this before starting
analysis to apply DDD assessment patterns.

## Exploration Patterns

Map the project structure before detecting issues.

### Entity / Model discovery

| Glob pattern | What it finds |
|--------------|---------------|
| `**/domain/**`, `**/entities/**`, `**/models/**`, `**/aggregates/**` | Domain layer |
| `**/services/**`, `**/application/**`, `**/usecases/**`, `**/handlers/**` | Application layer |
| `**/repositories/**`, `**/dal/**`, `**/persistence/**`, `**/infrastructure/**` | Data access layer |
| `**/dto/**`, `**/dtos/**`, `**/responses/**`, `**/contracts/**`, `**/api/**`, `**/viewmodels/**` | Transfer objects |

### ORM marker detection

| Language | Grep patterns |
|----------|---------------|
| JS/TS | `@Entity`, `@Table`, `@Column`, `@Document` |
| C# | `[Table]`, `[Key]`, `[Column]`, `DbContext`, `DbSet<` |
| Java | `@Entity`, `@Table`, `@MappedSuperclass`, `@Repository` |

### Boundary entry point detection

| Language | Grep patterns |
|----------|---------------|
| JS/TS | `express`, `fastify`, `Request, Response` |
| C# | `ControllerBase`, `[ApiController]`, `IActionResult` |
| Java | `@RestController`, `@Controller`, `@RequestMapping` |

### Application service detection

| Language | Grep patterns |
|----------|---------------|
| JS/TS | `@Injectable`, `@Service`, class names ending in `Service` |
| C# | Class names ending in `Service`, `Handler`, `UseCase` |
| Java | `@Service`, `@Component`, class names ending in `Service`, `Handler` |

If none of these patterns yield files, return skip.

## Anti-Pattern Recognition

### Business Logic Misplacement

Logic belongs in the domain layer. Flag when found in:

| Wrong location | Signal |
|---------------|--------|
| Controllers/routes | Discount calculations, validation rules, authorization logic in route handlers |
| Repositories/DAL | Business rules in SQL queries, computed columns, trigger-like logic |
| Application services | Rules that should be on an entity or domain service (application services orchestrate, they don't own rules) |

Exception: domain services legitimately own rules that span multiple entities.

### Anemic Domain Model

Entities that are pure data holders (only getters/setters) while services
contain all behavior. Signs:

- Entity has 10+ properties but 0 methods beyond accessors
- Service methods that take an entity, inspect its state, and return a decision
- External callers setting status fields directly instead of calling intention-revealing methods (`order.status = 'paid'` vs `order.markPaid()`)

### Abstraction Leaks

| Leak type | Signal |
|-----------|--------|
| ORM in domain | Domain objects with `@Column`, `[Table]`, persistence annotations |
| HTTP in domain | Domain objects importing `Request`, `Response`, HTTP status codes |
| Infrastructure in domain | Domain layer importing database clients, message queues, file I/O |

### Boundary Violations

| Violation | Signal |
|-----------|--------|
| Missing DTOs | Domain entities returned directly from API endpoints |
| Cross-context coupling | Direct imports between bounded contexts instead of events/shared kernel |
| Aggregate boundary bypass | Reaching into an aggregate's child entities directly |

### Ubiquitous Language Drift

Flag only internal inconsistency observable in code:

- Same concept with different names across modules (`Order` / `Purchase` / `Transaction`)
- Generic names where domain terms exist (`process`, `handle`, `data`, `info`, `manager`)

Do not flag terminology as wrong based on assumed business language.

### Supple Design Smells (Evans)

Design that's hard to change because intent isn't in the code:

- A domain method named for **how**, not **what** (`recalc`, `doProcess`,
  `update2`) — rename to an intention-revealing operation.
- A **boolean flag parameter** that switches behavior (`charge(amount, true)`) —
  split into two intention-revealing methods or a strategy.
- A **mutable value object**: a type used as a value (money, range, coordinate,
  date span) with public setters or in-place mutation — make it immutable; return
  new instances. Value objects compared by *value*, not identity.

### Implicit Concepts (missing Specification / Policy)

A named business rule hiding inside scattered conditionals:

- The same compound predicate (`if order.total > 100 && customer.tenureDays > 365
  && …`) repeated across services — surface it as a named **Specification**
  (`PreferredCustomerSpec.isSatisfiedBy(...)`) or **Policy** object.
- A constraint everyone "just knows" but that lives nowhere as a type — give it a
  name and a home. Implicit concepts are where bugs and language drift breed.

### Construction Without Invariants

Objects that can be built into an invalid state:

- A public constructor / setter chain that lets a caller create an entity missing
  required fields or violating a rule (negative balance, end-before-start) —
  enforce invariants in the constructor or a **Factory**; reject invalid input at
  construction, not later.
- An aggregate assembled field-by-field by an application service instead of via
  a factory method that guarantees a consistent whole.
