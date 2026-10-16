import { jsxRenderer } from 'hono/jsx-renderer';
import styles from '../styles/layout.module.css';
import layoutCss from '../styles/layout.module.css?inline';
import homeCss from '../styles/home.module.css?inline';

export default jsxRenderer(({ children }) => {
  return (
    <html lang='ja'>
      <head>
        <meta charSet='utf-8' />
        <meta name='viewport' content='width=device-width, initial-scale=1' />
        <style>{`${layoutCss}\n${homeCss}`}</style>
        <title>ORIOM MINECRAFT ACCESS</title>
      </head>
      <body class={styles.page}>
        <header class={styles.header}>
          <h1 class={styles.brand}>ORIOM MINECRAFT ACCESS</h1>
        </header>
        <main class={styles.main}>{children}</main>
        <p class={styles.disclaimer}>
          Minecraft の公式の 製品、サービスなどではありません。Mojang または Microsoft から承認を受けておらず、それとの関連性もありません。
        </p>
      </body>
    </html>
  );
});
