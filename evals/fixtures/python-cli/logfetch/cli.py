import click
import httpx
from rich.console import Console
from rich.table import Table

console = Console()

@click.group()
def main():
    """Fetch and display logs from remote services."""
    pass

@main.command()
@click.argument("url")
@click.option("--since", default="1h", help="Time range (e.g. 1h, 30m, 7d)")
@click.option("--format", "fmt", type=click.Choice(["table", "json", "raw"]), default="table")
def fetch(url: str, since: str, fmt: str):
    """Fetch logs from a remote endpoint."""
    response = httpx.get(url, params={"since": since}, timeout=30)
    response.raise_for_status()
    data = response.json()

    if fmt == "json":
        console.print_json(data=data)
    elif fmt == "raw":
        for entry in data.get("logs", []):
            click.echo(entry.get("message", ""))
    else:
        table = Table(title=f"Logs from {url}")
        table.add_column("Timestamp")
        table.add_column("Level")
        table.add_column("Message")
        for entry in data.get("logs", []):
            table.add_row(entry.get("ts", ""), entry.get("level", ""), entry.get("message", ""))
        console.print(table)

@main.command()
@click.argument("url")
def health(url: str):
    """Check if the log endpoint is reachable."""
    try:
        r = httpx.get(url, timeout=5)
        console.print(f"[green]OK[/green] — status {r.status_code}")
    except httpx.RequestError as e:
        console.print(f"[red]FAIL[/red] — {e}")
