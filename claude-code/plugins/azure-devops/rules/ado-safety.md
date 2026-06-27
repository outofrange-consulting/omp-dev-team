# Azure DevOps safety (always on for ADO work)

- Auth is the ambient **Azure CLI session** (`az login` / `DefaultAzureCredential`).
  Never read, echo, embed, or commit a PAT or token. Don't put credentials in a
  remote URL or a command line.
- Treat these as **destructive — confirm with the user first**: PR abandon,
  reject votes, force pushes, completing/merging a PR, and triggering a pipeline/build.
- Ground every claim about a PR / work item / build in its **actual fields from the
  MCP**, never a guess. If a tool returns an auth error, tell the user to run
  `az login` rather than retrying blindly.
