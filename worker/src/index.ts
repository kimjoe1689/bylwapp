import app from "./http";

export default {
  fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    return Promise.resolve(app.fetch(request, env, ctx));
  },
} satisfies ExportedHandler<Env>;
