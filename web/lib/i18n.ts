import catalog from "./translations.json" with { type: "json" };
import type { Locale } from "./locale";
function decode(source: string) {
  return source.replace(
    /&(amp|apos|quot|lt|gt|nbsp);/g,
    (_, name: string) =>
      ({ amp: "&", apos: "'", quot: '"', lt: "<", gt: ">", nbsp: " " })[name] ||
      _,
  );
}
const translations: Record<string, string> = Object.fromEntries(
  Object.entries(catalog).map(([zh, en]) => [decode(zh), decode(en)]),
);
const reverse = Object.fromEntries(
  Object.entries(translations).map(([zh, en]) => [en, zh]),
);
const feedbackPatterns: Array<[RegExp, string]> = [
  [/^Username @(.+) is already taken\.$/, "用户名 @{0} 已被使用。"],
  [/^A human account already exists for (.+)\.$/, "邮箱 {0} 已注册账号。"],
  [
    /^A verification code was already sent\. Try again in (\d+) seconds\.$/,
    "验证码已发送，请在 {0} 秒后重试。",
  ],
  [/^Verification code sent to (.+)\.$/, "验证码已发送至 {0}。"],
  [/^请求失败（(\d+)）$/, "请求失败（{0}）"],
];
export function translate(
  locale: Locale,
  source: string,
  ...values: unknown[]
): string {
  const key = decode(source).trim().replace(/\s+/g, " ");
  for (const [pattern, template] of feedbackPatterns) {
    const match = key.match(pattern);
    if (match) return translate(locale, template, ...match.slice(1));
  }
  const translated =
    locale === "en" ? translations[key] || key : reverse[key] || key;
  const text = translated.replace(/\{(\d+)\}/g, (match, index: string) =>
    Number(index) < values.length ? String(values[Number(index)] ?? "") : match,
  );
  return (
    (source.startsWith(" ") ? " " : "") +
    text +
    (source.endsWith(" ") ? " " : "")
  );
}
