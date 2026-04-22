import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";

export default defineConfig({
  site: "https://hiro-minami.github.io",
  base: "/moonshot-docs",
  integrations: [
    starlight({
      title: "Moonshot Docs",
      social: [
        { icon: "github", label: "GitHub", href: "https://github.com/hiro-minami/moonshot" },
      ],
      sidebar: [
        {
          label: "ADR (Architecture Decision Records)",
          autogenerate: { directory: "adr" },
        },
        {
          label: "Design Documents",
          autogenerate: { directory: "design" },
        },
      ],
    }),
  ],
});
