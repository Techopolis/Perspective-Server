# Contributing to Perspective Intelligence

Thank you for your interest in contributing to Perspective Intelligence! This project aims to make Apple Intelligence accessible through a standard OpenAI-compatible API, and community contributions are a big part of making that happen.

## Table of Contents

- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [How to Contribute](#how-to-contribute)
- [Code Style](#code-style)
- [Reporting Issues](#reporting-issues)
- [Pull Request Guidelines](#pull-request-guidelines)
- [Code of Conduct](#code-of-conduct)

## Getting Started

1. **Fork** the repository on GitHub
2. **Clone** your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/Perspective-Intelligence.git
   cd Perspective-Intelligence
   ```
3. **Create a branch** for your work:
   ```bash
   git checkout -b feature/your-feature-name
   ```

## Development Setup

### Requirements

- **macOS 26.0+** (Tahoe)
- **Xcode 26+** with Swift 6.0
- **Apple Silicon Mac** (M1 or later) with Apple Intelligence enabled

### Building

1. Open `Perspective Intelligence.xcodeproj` in Xcode
2. Select the **Perspective Intelligence** scheme
3. Build and run (`Cmd + R`)

The app will appear in your menu bar and automatically start the local server on port 11434.

### Testing your changes

- Verify the server starts and responds to requests:
  ```bash
  curl http://localhost:11434/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"model": "apple.local", "messages": [{"role": "user", "content": "Hello"}]}'
  ```
- Test the built-in chat UI by clicking the menu bar icon and opening the chat window
- Enable **Debug Logging** in Settings to see request/response details in the Xcode console

## How to Contribute

### Bug Fixes

Found a bug? Great catches are always welcome. Please:
1. Check the [existing issues](https://github.com/Techopolis-Online/Perspective-Intelligence/issues) to see if it's already reported
2. If not, open a new issue using the **Bug Report** template
3. If you'd like to fix it yourself, mention that in the issue and submit a PR

### New Features

Have an idea? We'd love to hear it:
1. Open an issue using the **Feature Request** template to discuss the idea first
2. Once there's agreement on the approach, implement it and submit a PR
3. Keep features focused -- one feature per PR is easier to review

### Documentation

Improvements to documentation, code comments, or examples are always valuable. No issue required -- just open a PR.

## Code Style

- **Swift 6.0** -- Use modern Swift concurrency (`async`/`await`, actors, `Sendable`)
- **SwiftUI** -- All UI code uses SwiftUI. Follow declarative patterns.
- **No third-party dependencies** -- This project intentionally has zero external dependencies. Please do not introduce any.
- **Follow existing patterns** -- Look at how the existing code is structured and match that style:
  - Actors for thread-safe shared state (`LocalHTTPServer`)
  - `ObservableObject` with `@Published` for UI state (`ServerController`, `ChatViewModel`)
  - `@AppStorage` for persisted preferences
  - `OSLog` for structured logging
- **Naming** -- Use descriptive names. Follow Swift API Design Guidelines.
- **Comments** -- Add `// MARK:` sections to organize code. Document non-obvious logic.
- **Access control** -- Use `private` by default. Only expose what's necessary.

## Reporting Issues

When reporting issues, please include:

- **macOS version** (must be 26.0+)
- **Hardware** (which Apple Silicon chip)
- **Steps to reproduce** the problem
- **Expected behavior** vs. **actual behavior**
- **Console output** if relevant (enable Debug Logging in Settings)
- **Screenshots** if applicable

Use the [Bug Report](https://github.com/Techopolis-Online/Perspective-Intelligence/issues/new?template=bug_report.md) template when opening an issue.

## Pull Request Guidelines

1. **One concern per PR** -- Keep pull requests focused on a single change
2. **Branch from `main`** -- Create your feature branch from the latest `main`
3. **Write a clear description** -- Explain what your PR does and why
4. **Test your changes** -- Verify the server starts, responds to API calls, and the chat UI works
5. **No breaking changes** -- The `/v1/chat/completions` endpoint format must remain compatible
6. **Keep it clean** -- No debug prints, commented-out code, or unrelated formatting changes
7. **Update documentation** -- If your change affects usage, update the README or relevant docs

### PR Process

1. Push your branch to your fork
2. Open a Pull Request against `main` on the upstream repository
3. Fill out the PR template with a description of your changes
4. Wait for review -- maintainers will provide feedback
5. Address any requested changes
6. Once approved, a maintainer will merge your PR

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code. Please report unacceptable behavior to the project maintainers.

---

Thank you for contributing to Perspective Intelligence!
