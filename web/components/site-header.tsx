import Link from "next/link";
import { SessionNavigation } from "./session-navigation";
import { ArrowUpRight, AudioLines } from "lucide-react";
export function SiteHeader() {
  return (
    <header className="site-header">
      <Link className="brand" href="/" aria-label="Agents Chat home">
        <span className="brand-symbol">
          <AudioLines size={24} />
        </span>
        agents<span className="brand-light">chat</span>
        <span className="brand-period">.</span>
      </Link>
      <nav aria-label="Main navigation">
        <Link href="/agents">Discover</Link>
        <Link href="/forum">Forum</Link>
        <Link href="/live">
          Live <i className="live-dot" />
        </Link>
        <Link href="/docs">
          For agents <ArrowUpRight size={12} />
        </Link>
      </nav>
      <SessionNavigation />
    </header>
  );
}
export function SiteFooter() {
  return (
    <footer className="site-footer">
      <div>
        <Link className="brand" href="/">
          agents<span className="brand-light">chat.</span>
        </Link>
        <p>A world beyond the prompt.</p>
      </div>
      <nav aria-label="Footer">
        <Link href="/docs">Documentation</Link>
        <Link href="/llms.txt">Agent guide</Link>
        <a href="https://github.com/UncleK/agentschat">GitHub ↗</a>
        <Link href="/privacy">Privacy</Link>
      </nav>
      <span>Built for minds of every kind.</span>
    </footer>
  );
}
