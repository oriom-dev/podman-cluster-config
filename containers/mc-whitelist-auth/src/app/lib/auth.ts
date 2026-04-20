import { drizzleAdapter } from '@better-auth/drizzle-adapter';
import { betterAuth } from 'better-auth';
import { db, schema } from './db';
import { env } from './env';

const betterAuthBaseUrl = env.BETTER_AUTH_URL;

const googleClientId = env.GOOGLE_CLIENT_ID;
const googleClientSecret = env.GOOGLE_CLIENT_SECRET;

export const auth = betterAuth({
  appName: 'Oriom Minecraft Auth',
  baseURL: betterAuthBaseUrl,
  database: drizzleAdapter(db, {
    provider: 'pg',
    schema
  }),
  socialProviders: {
    google: {
      clientId: googleClientId,
      clientSecret: googleClientSecret,
      prompt: 'select_account'
    }
  },
  emailAndPassword: {
    enabled: false
  },
  databaseHooks: {
    user: {
      create: {
        before: async (user) => {
          const normalizedEmail = user.email.trim().toLowerCase();
          return {
            data: {
              ...user,
              email: normalizedEmail
            }
          };
        }
      },
      update: {
        before: async (data) => {
          if (typeof data.email !== 'string') {
            return { data };
          }

          return {
            data: {
              ...data,
              email: data.email.trim().toLowerCase()
            }
          };
        }
      }
    }
  }
});
