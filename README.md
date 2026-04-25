# ControleHub

**Lightweight SQL Server Monitoring --- Built for Control, Not
Complexity**

------------------------------------------------------------------------

## The Problem

Most SQL Server monitoring tools try to do everything: - deep telemetry\
- complex alerting engines\
- heavy infrastructure

And in doing so, they often become: - expensive\
- opaque\
- operationally heavy

For many environments, that's overkill.

------------------------------------------------------------------------

## Why I Built This

After 20+ years as a DBA, I wanted something simpler:

-   full visibility across my SQL estate\
-   no agents\
-   no licensing\
-   no black boxes

Just **clear, controllable monitoring** using tools every DBA already
understands.

------------------------------------------------------------------------

## What ControleHub Is

ControleHub is a **lightweight, agentless monitoring framework** built
with:

-   PowerShell\
-   T-SQL\
-   SQL Server

It collects health, performance, and configuration data from multiple
SQL Server instances and centralises it into a single database for
reporting and analysis.

> This is not a replacement for enterprise tools --- it's a deliberate
> alternative for teams that value **control, transparency, and low
> footprint**.

------------------------------------------------------------------------

## What It Monitors

-   SQL Agent job status, duration, and anomalies\
-   Backup history and backup age\
-   AlwaysOn Availability Group health\
-   Data file usage and growth\
-   Disk capacity and utilisation\
-   Windows service states\
-   Failover cluster state\
-   SQL Server availability (lightweight connectivity checks)

------------------------------------------------------------------------

## Architecture (Simple by Design)

**Hub-and-Spoke Model**

-   **Hub** → Central SQL Server database (ControleHub)\
-   **Spokes** → Monitored SQL Server instances\
-   **Orchestration** → PowerShell scripts running on a scheduler

**Flow:** 1. Read active servers from a central table\
2. Connect to each instance\
3. Execute targeted diagnostic queries\
4. Store results in central staging tables

No agents. No changes to monitored instances (beyond permissions).

------------------------------------------------------------------------

## Key Design Principles

-   **Agentless** -- nothing installed on monitored servers\
-   **Transparent** -- all logic is visible and editable\
-   **Low footprint** -- minimal impact on production systems\
-   **Modular** -- each monitoring domain is independent\
-   **Practical** -- built by a DBA for real-world operations

------------------------------------------------------------------------

## Trade-offs (Intentional)

-   Uses **truncate-and-load** → prioritises current state over history\
-   Uses **NOLOCK** → prioritises low impact over strict consistency\
-   Centralised hub → simpler architecture, but introduces a dependency\
-   Sequential execution → simpler logic, less scalable at very large
    scale\
-   No built-in alerting → designed to integrate with your existing
    processes

------------------------------------------------------------------------

## What This Is NOT

-   Not a full enterprise monitoring suite\
-   Not a real-time alerting system\
-   Not plug-and-play for non-technical users\
-   Not designed for hyperscale environments out of the box\
-   Not a historical analytics platform (by default)

This is a **framework**, not a finished product.

------------------------------------------------------------------------

## Security Note

Basic sanitisation is applied in script-based inserts.\
For production hardening, **parameterised queries are recommended**.

Authentication: - Windows Integrated Security (default)\
- SQL Authentication (optional)

------------------------------------------------------------------------

## Quick Start (5--10 Minutes)

1.  Create the **ControleHub** database\

2.  Run the provided `.sql` deployment script\

3.  Populate `dbo.ServerList` with your SQL instances\

4.  Update:

    ``` powershell
    $MonitorServer
    $MonitorDatabase
    ```

5.  Run any `Monitor-*.ps1` script manually\

6.  Schedule via SQL Server Agent or Task Scheduler

------------------------------------------------------------------------

## Example Use Case

In a mid-sized environment (\~40 SQL instances), this approach: -
eliminated manual health checks\
- surfaced failing jobs and disk pressure early\
- provided a central source of truth

------------------------------------------------------------------------

## Who This Is For

-   DBAs who prefer **control over abstraction**\
-   Teams avoiding licensing overhead\
-   Environments where PowerShell + T-SQL are standard

------------------------------------------------------------------------

## Who This Is NOT For

-   Teams needing turnkey, fully managed monitoring\
-   Organisations requiring enterprise-grade alerting out of the box\
-   Environments without PowerShell or SQL Server expertise

------------------------------------------------------------------------

## Extending ControleHub

-   Add new monitoring modules\
-   Introduce history tables\
-   Build alerting via SQL Agent or external systems\
-   Layer reporting tools on top

------------------------------------------------------------------------

## Final Thought

> Monitoring doesn't need to be complex to be effective.\
> Sometimes, **clarity beats capability**.

------------------------------------------------------------------------

## License

Provided AS-IS. Use, modify, and extend at your own discretion.
