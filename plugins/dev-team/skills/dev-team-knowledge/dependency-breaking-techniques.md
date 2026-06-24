# Dependency-Breaking Techniques

The full catalog for getting legacy code under test by introducing **seams**.
Adapted from *Working Effectively with Legacy Code* (Feathers). The `legacy-code`
skill summarizes the most common five; this is the reference to resolve a
specific blocker.

## Principle

Break the **smallest** dependency that gets the code under test **while
preserving behavior**. Every break is temporary scaffolding; once tests exist,
refactor toward a clean design. Prefer the lowest-risk technique that works
(Extract Method / Extract Interface before subclassing).

## How to choose (by what blocks you)

| Blocker | Reach for |
|---|---|
| Collaborator constructed **inside** the class/method | Parameterize Constructor / Method; Extract & Override Factory Method |
| Concrete, non-substitutable type | Extract Interface; Extract Implementer; Adapt Parameter |
| Global / singleton / static reference | Encapsulate Global References; Introduce Static Setter; Replace Global Ref with Getter |
| Method/class too large to instantiate or follow | Break Out Method Object; Sprout/Wrap Method or Class |
| Unconstructable parameter | Pass null / Adapt Parameter / Primitivize Parameter |
| Compiled/procedural language, few seams | Link Substitution; Function Pointer; Definition Completion |

## The catalog (grouped)

- **Add behavior without touching untested code:** Sprout Method, Sprout Class,
  Wrap Method, Wrap Class.
- **Break a created/obtained collaborator:** Parameterize Constructor,
  Parameterize Method, Extract & Override Call, Extract & Override Factory
  Method, Extract & Override Getter, Supersede Instance Variable.
- **Substitute a type:** Extract Interface, Extract Implementer, Subclass &
  Override Method.
- **Tame globals/singletons/statics:** Encapsulate Global References, Replace
  Global Reference with Getter, Introduce Static Setter, Introduce Instance
  Delegator, Expose Static Method.
- **Hard parameters & big methods:** Adapt Parameter, Primitivize Parameter,
  Break Out Method Object, Pull Up Feature, Push Down Dependency.
- **Non-OO / compiled / interpreted seams:** Link Substitution, Replace Function
  with Function Pointer, Definition Completion, Template Redefinition, Text
  Redefinition.

## Most common in practice

Extract Interface · Parameterize Constructor · Subclass & Override Method ·
Extract & Override Call/Factory · Sprout/Wrap Method · Adapt Parameter.

## Connections

- The change algorithm and characterization tests → `legacy-code` skill,
  `legacy-test-strategy.md` (if present).
- Making the seam testable → `testability-patterns.md`, `test-doubles.md`.
