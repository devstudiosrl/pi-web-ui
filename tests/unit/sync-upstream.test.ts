import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";

/**
 * scripts/sync-upstream.sh — the one command this fork depends on.
 *
 * A fork nobody rebases becomes a photograph: three months on, upstream has
 * moved fifty files, a fix lands there, and the patches can no longer be
 * carried over. So the sync has to keep working, and the way to know it does
 * is to run it — against a throwaway pair of repositories, not against the
 * real upstream, so the test costs milliseconds and needs no network.
 *
 * What it checks is exactly what would be broken if the script rotted: the
 * Printalo commits are replayed on top of the upstream release that declares
 * the target version, and the tag that comes out is named after that version.
 */
const RADICE = join(__dirname, "..", "..");
const CASA = mkdtempSync(join(tmpdir(), "sync-upstream-"));

afterAll(() => rmSync(CASA, { recursive: true, force: true }));

function git(cwd: string, ...args: string[]): string {
	return execFileSync("git", args, {
		cwd,
		encoding: "utf8",
		env: {
			...process.env,
			GIT_AUTHOR_NAME: "prova",
			GIT_AUTHOR_EMAIL: "prova@example.invalid",
			GIT_COMMITTER_NAME: "prova",
			GIT_COMMITTER_EMAIL: "prova@example.invalid",
		},
	}).trim();
}

function versione(cartella: string, v: string, extra?: string) {
	writeFileSync(join(cartella, "package.json"), `{\n\t"name": "pi-web-ui",\n\t"version": "${v}"\n}\n`);
	if (extra) writeFileSync(join(cartella, extra), `${extra}\n`);
}

describe("sync-upstream.sh", () => {
	// A fake upstream with two releases, and a fork whose `printalo` branch
	// carries one patch on top of the first one.
	const monte = join(CASA, "upstream");
	const fork = join(CASA, "fork");
	mkdirSync(monte);
	git(monte, "init", "-q", "-b", "main");
	// The runner has no global git identity: without this the tag in the second
	// run fails and the failure looks like a broken script. Setting it in the
	// repositories themselves means every git command works, whoever runs it.
	git(monte, "config", "user.name", "prova");
	git(monte, "config", "user.email", "prova@example.invalid");
	versione(monte, "0.1.0");
	git(monte, "add", "-A");
	git(monte, "commit", "-q", "-m", "release 0.1.0");

	git(CASA, "clone", "-q", monte, fork);
	git(fork, "config", "user.name", "prova");
	git(fork, "config", "user.email", "prova@example.invalid");
	git(fork, "remote", "add", "upstream", monte);
	git(fork, "checkout", "-q", "-b", "printalo");
	writeFileSync(join(fork, "PATCHES.md"), "the printalo patch\n");
	git(fork, "add", "-A");
	git(fork, "commit", "-q", "-m", "printalo: a patch of ours");

	// Upstream publishes 0.2.0 while we were away.
	versione(monte, "0.2.0", "nuovo-a-monte.txt");
	git(monte, "add", "-A");
	git(monte, "commit", "-q", "-m", "release 0.2.0");

	const uscita = execFileSync("bash", [join(RADICE, "scripts", "sync-upstream.sh"), "0.2.0", "--no-build"], {
		cwd: fork,
		encoding: "utf8",
		env: { ...process.env, GIT_AUTHOR_NAME: "prova", GIT_AUTHOR_EMAIL: "prova@example.invalid", GIT_COMMITTER_NAME: "prova", GIT_COMMITTER_EMAIL: "prova@example.invalid" },
	});

	it("replays the Printalo commits on top of the upstream release", () => {
		expect(uscita).toContain("target version: 0.2.0");
		// Our patch is still there, and it is on top of the new release.
		const log = git(fork, "log", "--oneline", "printalo");
		expect(log).toContain("printalo: a patch of ours");
		expect(log).toContain("release 0.2.0");
		// The upstream file arrived: this is a rebase, not a copy of the old tree.
		expect(git(fork, "show", "printalo:nuovo-a-monte.txt")).toContain("nuovo-a-monte");
		// And the patch really sits above the release, not below it.
		const ordine = git(fork, "log", "--format=%s", "printalo").split("\n");
		expect(ordine[0]).toBe("printalo: a patch of ours");
		expect(ordine[1]).toBe("release 0.2.0");
	});

	it("names the tag after the upstream version", () => {
		expect(git(fork, "tag", "--list")).toContain("v0.2.0-printalo.1");
	});

	it("says there is nothing to do when it is already in sync", () => {
		const seconda = execFileSync("bash", [join(RADICE, "scripts", "sync-upstream.sh"), "0.2.0", "--no-build"], {
			cwd: fork,
			encoding: "utf8",
		});
		expect(seconda).toContain("already sits on 0.2.0");
		// The second run must not reuse the first tag.
		expect(git(fork, "tag", "--list")).toContain("v0.2.0-printalo.2");
	});
});
