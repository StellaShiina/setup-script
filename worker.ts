export default {
  async fetch(request: Request, env: any): Promise<Response> {
    // 强制请求 install.sh（无论用户访问什么路径）
    const url = new URL(request.url);
    url.pathname = "/init.sh";

    return env.ASSETS.fetch(new Request(url.toString(), request));
  },
};