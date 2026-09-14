# Contributing to IntuneOps

Thanks for your interest in contributing! Here's how to get started.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/<your-user>/IntuneOps.git`
3. Create a feature branch: `git checkout -b feature/my-feature`
4. Make your changes
5. Run tests: `Invoke-Pester ./tests/`
6. Commit: `git commit -m "Add my feature"`
7. Push: `git push origin feature/my-feature`
8. Open a Pull Request

## Prerequisites

- PowerShell 7+
- Microsoft.Graph PowerShell SDK (`Install-Module Microsoft.Graph`)
- Pester 5+ for running tests (`Install-Module Pester`)

## Code Standards

- Follow [PowerShell Best Practices](https://poshcode.gitbook.io/powershell-practice-and-style/)
- Use `Verb-Noun` naming for functions
- Add comment-based help (`<# .SYNOPSIS ... #>`) to every public function
- Write Pester tests for new functionality
- Keep functions focused — one function, one job

## Reporting Issues

- Use the **Bug Report** or **Feature Request** issue templates
- Include PowerShell version (`$PSVersionTable`), OS, and Graph SDK version
- Paste error messages in full

## Pull Request Guidelines

- Reference the issue number in your PR description
- Keep PRs focused on a single change
- Ensure all Pester tests pass before requesting review
- Update docs if you change script parameters or behavior

## Code of Conduct

Be respectful, constructive, and inclusive. We're all here to make endpoint management less painful.
