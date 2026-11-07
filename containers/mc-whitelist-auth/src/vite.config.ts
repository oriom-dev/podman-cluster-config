import build from '@hono/vite-build/cloudflare-workers'
import cloudflareAdapter from '@hono/vite-dev-server/cloudflare'
import nodeAdapter from '@hono/vite-dev-server/node'
import tailwindcss from '@tailwindcss/vite'
import honox from 'honox/vite'
import { defineConfig } from 'vite'

export default defineConfig(({ mode }) => ({
  plugins: [
    honox({
      devServer: { adapter: mode === 'ui' ? nodeAdapter : cloudflareAdapter },
      client: { input: ['/app/client.ts', '/app/style.css'] }
    }),
    tailwindcss(),
    build()
  ]
}))
