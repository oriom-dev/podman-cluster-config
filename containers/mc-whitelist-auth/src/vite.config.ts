import build from '@hono/vite-build/node'
import adapter from '@hono/vite-dev-server/node'
import honox from 'honox/vite'
import { defineConfig } from 'vite'

export default defineConfig({
  ssr: {
    external: ['pg']
  },
  plugins: [
    honox({
      devServer: { adapter },
      client: { input: ['/app/client.ts'] }
    }),
    build()
  ]
})
