# Contributing to gRPCServer.jl

Thank you for your interest in contributing to gRPCServer.jl! This document provides guidelines and instructions for contributing.

## Code of Conduct

By participating in this project, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

## Getting Started

### Prerequisites

- Julia 1.10 or later
- Git

### Development Setup

1. Fork and clone the repository:

   ```bash
   git clone https://github.com/s-celles/gRPCServer.jl.git
   cd gRPCServer.jl
   ```

2. Start Julia and activate the project:

   ```julia
   using Pkg
   Pkg.activate(".")
   Pkg.instantiate()
   ```

3. For running tests, you may also want to instantiate test dependencies:

   ```julia
   Pkg.instantiate(; test=true)
   ```

## Code Coverage

### Viewing Coverage in Codecov

Code coverage is automatically collected and uploaded to Codecov during CI runs. To view coverage:

1. Open a Pull Request - coverage status will appear in PR checks
2. Click "Details" on the Codecov status check to see the full report
3. Visit the [Codecov Dashboard](https://codecov.io/gh/s-celles/gRPCServer.jl) to see:
   - Project-wide coverage percentage
   - Per-file coverage breakdown
   - Line-by-line coverage highlighting
   - Historical coverage trends

### Running Coverage Locally

Run tests with coverage enabled:

```julia
using Pkg
Pkg.test("gRPCServer"; coverage=true)
```

Or from the command line:

```bash
julia --project -e 'using Pkg; Pkg.test(coverage=true)'
```

This generates `.cov` files in the `src/` directory.

### Generating Local Coverage Reports

To view coverage locally with detailed reports:

```julia
using Pkg
Pkg.test("gRPCServer"; coverage=true)

# Process coverage data
using Coverage
coverage = process_folder("src")

# View summary
covered_lines, total_lines = get_summary(coverage)
println("Coverage: $(round(covered_lines/total_lines * 100, digits=1))%")

# Generate lcov file (compatible with coverage tools)
LCOV.writefile("lcov.info", coverage)
```

To generate an HTML report for browsing locally:

```julia
using Coverage
coverage = process_folder("src")
Coverage.html_report(coverage; dir="coverage_html")
# Open coverage_html/index.html in your browser
```

**Note**: For local coverage reports, you may need to add Coverage.jl to your global environment:

```julia
using Pkg
Pkg.add("Coverage")
```

### Coverage Thresholds

The project enforces coverage standards via Codecov:

- **Project coverage target**: 70% (informational, not blocking)
- **Patch coverage target**: 80% (new code should be well-tested)
- **Coverage decrease tolerance**: 1% (minor fluctuations allowed)

These thresholds are configured in `.codecov.yml`. PRs will show coverage status checks, but they are informational and won't block merging.

### Codecov Token Setup (Optional)

For repository maintainers: To prevent rate limiting during high CI activity, you can configure a Codecov token:

1. Get the repository token from Codecov settings
2. Add `CODECOV_TOKEN` as a repository secret in GitHub
3. Update the CI workflow to pass the token (optional, works without it for public repos)

## Running Tests

### All Tests

```julia
using Pkg
Pkg.test("gRPCServer")
```

Or from the command line:

```bash
julia --project -e 'using Pkg; Pkg.test()'
```

### Specific Test Files

You can run specific test files directly:

```julia
include("test/unit/test_config.jl")
```

### Test Structure

- `test/unit/` - Unit tests for individual components
- `test/integration/` - Integration tests for full workflows
- `test/contract/` - Contract tests (e.g., grpcurl compatibility)
- `test/aqua.jl` - Code quality checks via Aqua.jl

## Building Documentation

```bash
julia --project=docs -e '
    using Pkg
    Pkg.develop(PackageSpec(path=pwd()))
    Pkg.instantiate()'

julia --project=docs docs/make.jl
```

Documentation will be generated in `docs/build/`.

## Making Changes

### Branching Strategy

1. Create a feature branch from `main`:

   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes with clear, focused commits.

3. Push your branch and open a pull request.

### Commit Messages

We use [Conventional Commits](https://www.conventionalcommits.org/). Format your commit messages as:

```
<type>: <description>

[optional body]

[optional footer(s)]
```

Types:
- `feat:` - New features
- `fix:` - Bug fixes
- `refactor:` - Code refactoring without behavior changes
- `docs:` - Documentation changes
- `test:` - Adding or updating tests
- `chore:` - Maintenance tasks, CI changes, etc.

Examples:
```
feat: add support for gzip compression
fix: correct HPACK table index calculation
docs: update TLS configuration examples
test: add integration tests for streaming RPCs
```

### Code Style

- Follow standard Julia conventions and style guidelines
- Use 4 spaces for indentation
- Keep lines under 92 characters when practical
- Use descriptive variable and function names
- Add docstrings for public functions and types
- Ensure type stability in performance-critical paths

### Pull Request Guidelines

1. **Ensure tests pass**: All existing tests must pass, and new functionality should include tests.

2. **Update documentation**: If your changes affect the public API, update the relevant documentation.

3. **Keep PRs focused**: Each PR should address a single concern. Split large changes into smaller, reviewable PRs.

4. **Write a clear description**: Explain what your PR does, why it's needed, and any relevant context.

5. **Reference issues**: If your PR addresses an issue, reference it in the description (e.g., "Fixes #123").

## Project Structure

```
gRPCServer.jl/
├── src/
│   ├── gRPCServer.jl     # Main module
│   ├── server.jl         # Server implementation
│   ├── config.jl         # Configuration types
│   ├── context.jl        # Request context
│   ├── dispatch.jl       # Method dispatch
│   ├── streams.jl        # Streaming support
│   ├── errors.jl         # Error types
│   ├── compression.jl    # Compression support
│   ├── interceptors.jl   # Interceptor framework
│   ├── http2/            # HTTP/2 protocol implementation
│   ├── tls/              # TLS configuration
│   ├── proto/            # Generated protobuf types
│   └── services/         # Built-in services (health, reflection)
├── test/                 # Test suite
├── docs/                 # Documentation
└── specs/                # Design specifications
```

## Types of Contributions

### Bug Reports

When filing a bug report, please include:
- Julia version (`versioninfo()`)
- gRPCServer.jl version
- Operating system
- Minimal reproducible example
- Expected vs actual behavior

### Feature Requests

Feature requests are welcome! Please describe:
- The use case and motivation
- Proposed solution (if any)
- Alternatives considered

### Documentation

Documentation improvements are always appreciated:
- Fix typos or unclear explanations
- Add examples
- Improve API documentation

## Questions?

If you have questions about contributing, feel free to:
- Open a discussion on GitHub
- File an issue with the "question" label

Thank you for contributing to gRPCServer.jl!
