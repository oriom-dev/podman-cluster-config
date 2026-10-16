import { createRoute } from 'honox/factory';
import Counter from '../islands/counter';

export default createRoute((c) => {
  return c.render(
    <main class="mx-auto max-w-xl p-8">
      <h1 class="text-2xl font-bold">Oriom Minecraft</h1>
      <p class="mt-2 text-slate-600">認証機能は準備中です。</p>
      <Counter />
    </main>
  );
});
