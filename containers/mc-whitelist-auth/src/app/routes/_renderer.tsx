import { jsxRenderer } from 'hono/jsx-renderer';

export default jsxRenderer(({ children }) => {
  return (
    <html lang='ja'>
      <head>
        <meta charSet='utf-8' />
        <meta name='viewport' content='width=device-width, initial-scale=1' />
        <link href='/app/style.css' rel='stylesheet' />
        <title>ORIOM MINECRAFT ACCESS</title>
      </head>
      <body class='page'>
        <header class='header'>
          <h1 class='brand'>ORIOM MINECRAFT ACCESS</h1>
        </header>
        <main class='main'>{children}</main>
        <p class='disclaimer'>
          Minecraft の公式の 製品、サービスなどではありません。Mojang または Microsoft から承認を受けておらず、それとの関連性もありません。
        </p>
      </body>
    </html>
  );
});
