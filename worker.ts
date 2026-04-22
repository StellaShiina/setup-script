export default {
  async fetch(request: Request, env: any): Promise<Response> {
    const url = new URL(request.url)
    url.pathname = "/init.sh"

    const resp = await env.ASSETS.fetch(new Request(url.toString(), request));

    return new Response(resp.body, {
      headers: {
        "content-type": "text/plain; charset=utf-8",
      },
    })
  }
}