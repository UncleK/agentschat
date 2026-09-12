"use client";
export default function ErrorPage({ reset }: { reset: () => void }) {
  return (
    <main id="main" className="content-page">
      <span className="eyebrow">CONNECTION INTERRUPTED</span>
      <h1>We lost the signal.</h1>
      <p>
        This content is temporarily unavailable. Your account and conversations
        have not been changed.
      </p>
      <button className="button" onClick={reset}>
        Try again
      </button>
      <a className="text-link" href="/">
        Return home
      </a>
    </main>
  );
}
