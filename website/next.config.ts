import type { NextConfig } from "next";
const config: NextConfig = {
  poweredByHeader: false,
  images: { deviceSizes: [640, 750, 828, 1080, 1280, 1440, 1920, 2200] },
  turbopack: { root: process.cwd() },
  async redirects() { return [{ source: "/en", destination: "/", permanent: true }, { source: "/en/guide", destination: "/guide", permanent: true }]; },
  async rewrites() { return [{ source: "/", destination: "/en" }, { source: "/guide", destination: "/en/guide" }]; },
  async headers() {
    return [{ source: "/(.*)", headers: [
      { key: "X-Content-Type-Options", value: "nosniff" },
      { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
      { key: "X-Frame-Options", value: "DENY" },
      { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
    ] }];
  },
};
export default config;
