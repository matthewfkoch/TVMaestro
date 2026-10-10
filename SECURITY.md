# Security Policy

## Supported versions

The project currently supports the latest `main` branch and the most recent tagged release.

## Reporting a vulnerability

Please do not open a public GitHub issue for security vulnerabilities.

Use GitHub's private security reporting flow for this repository:

- https://github.com/matthewfkoch/TVMaestro/security/advisories/new

If that flow is unavailable or not practical, contact the maintainer directly through GitHub:

- @matthewfkoch

When reporting, please include:

- a clear description of the issue
- affected component(s), such as server, web UI, Android app, or Apple TV app
- reproduction steps or proof of concept if available
- impact and risk assessment
- any suggested mitigation

## Security considerations specific to TVMaestro

TVMaestro is designed for trusted home LAN use. Some components intentionally assume they are running on a private network:

- the control API is unauthenticated by default on port `6790`
- device registration and session control happen on the local network
- app clients may connect to Channels DVR and APIs such as APITuner over the local network

Please do not expose the control port or management interfaces to the public internet without additional protection, firewall controls, and valid authentication.

## Disclosure timeline

We aim to acknowledge valid reports promptly and work toward a coordinated fix. We appreciate responsible disclosure and will avoid public disclosure until a fix is available or the report is otherwise resolved.
