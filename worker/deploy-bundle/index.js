var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

// ../../../workspace/worker/node_modules/hono/dist/http-exception.js
var HTTPException = class extends Error {
  static {
    __name(this, "HTTPException");
  }
  res;
  status;
  /**
  * Creates an instance of `HTTPException`.
  * @param status - HTTP status code for the exception. Defaults to 500.
  * @param options - Additional options for the exception.
  */
  constructor(status = 500, options) {
    super(options?.message, { cause: options?.cause });
    this.res = options?.res;
    this.status = status;
  }
  /**
  * Returns the response object associated with the exception.
  * If a response object is not provided, a new response is created with the error message and status code.
  * @returns The response object.
  */
  getResponse() {
    if (this.res) return new Response(this.res.body, {
      status: this.status,
      headers: this.res.headers
    });
    return new Response(this.message, { status: this.status });
  }
};

// ../../../workspace/worker/node_modules/hono/dist/request/constants.js
var GET_MATCH_RESULT = /* @__PURE__ */ Symbol();

// ../../../workspace/worker/node_modules/hono/dist/utils/buffer.js
var bufferToFormData = /* @__PURE__ */ __name((arrayBuffer, contentType) => {
  return new Response(arrayBuffer, { headers: { "Content-Type": contentType.replace(/^[^;]+/, (mediaType) => mediaType.toLowerCase()) } }).formData();
}, "bufferToFormData");

// ../../../workspace/worker/node_modules/hono/dist/utils/body.js
var MAX_NESTED_OBJECTS = 1e4;
var isRawRequest = /* @__PURE__ */ __name((request) => "headers" in request, "isRawRequest");
var parseBody = /* @__PURE__ */ __name(async (request, options = /* @__PURE__ */ Object.create(null)) => {
  const { all = false, dot = false } = options;
  const mediaType = (isRawRequest(request) ? request.headers : request.raw.headers).get("Content-Type")?.split(";")[0].trim().toLowerCase();
  if (mediaType === "multipart/form-data" || mediaType === "application/x-www-form-urlencoded") return parseFormData(request, {
    all,
    dot
  });
  return {};
}, "parseBody");
async function parseFormData(request, options) {
  if (!isRawRequest(request) && request.bodyCache.formData) return convertFormDataToBodyData(await request.bodyCache.formData, options);
  const headers = isRawRequest(request) ? request.headers : request.raw.headers;
  const arrayBuffer = await request.arrayBuffer();
  const formDataPromise = bufferToFormData(arrayBuffer, headers.get("Content-Type") || "");
  if (!isRawRequest(request)) request.bodyCache.formData = formDataPromise;
  const formData = await formDataPromise;
  if (formData) return convertFormDataToBodyData(formData, options);
  return {};
}
__name(parseFormData, "parseFormData");
function convertFormDataToBodyData(formData, options) {
  const form = /* @__PURE__ */ Object.create(null);
  const nestingState = { count: 0 };
  formData.forEach((value, key) => {
    if (!(options.all || key.endsWith("[]"))) form[key] = value;
    else handleParsingAllValues(form, key, value);
  });
  if (options.dot) Object.entries(form).forEach(([key, value]) => {
    if (key.includes(".")) {
      handleParsingNestedValues(form, key, value, nestingState);
      delete form[key];
    }
  });
  return form;
}
__name(convertFormDataToBodyData, "convertFormDataToBodyData");
var handleParsingAllValues = /* @__PURE__ */ __name((form, key, value) => {
  if (form[key] !== void 0) {
    if (Array.isArray(form[key])) form[key].push(value);
    else form[key] = [form[key], value];
  } else if (!key.endsWith("[]")) form[key] = value;
  else form[key] = [value];
}, "handleParsingAllValues");
var handleParsingNestedValues = /* @__PURE__ */ __name((form, key, value, state) => {
  if (/(?:^|\.)(?:__proto__|constructor\.prototype)\./.test(key)) return;
  let nestedForm = form;
  const keys = key.split(".", 34);
  if (keys.length > 33) throwNestingLimitExceeded();
  keys.forEach((key2, index) => {
    if (index === keys.length - 1) nestedForm[key2] = value;
    else {
      if (!nestedForm[key2] || typeof nestedForm[key2] !== "object" || Array.isArray(nestedForm[key2]) || nestedForm[key2] instanceof File) {
        if (state.count++ >= MAX_NESTED_OBJECTS) throwNestingLimitExceeded();
        nestedForm[key2] = /* @__PURE__ */ Object.create(null);
      }
      nestedForm = nestedForm[key2];
    }
  });
}, "handleParsingNestedValues");
var throwNestingLimitExceeded = /* @__PURE__ */ __name(() => {
  throw new Error("Nesting limit exceeded");
}, "throwNestingLimitExceeded");

// ../../../workspace/worker/node_modules/hono/dist/utils/url.js
var splitPath = /* @__PURE__ */ __name((path) => {
  const paths = path.split("/");
  if (paths[0] === "") paths.shift();
  return paths;
}, "splitPath");
var splitRoutingPath = /* @__PURE__ */ __name((routePath2) => {
  const { groups, path } = extractGroupsFromPath(routePath2);
  const paths = splitPath(path);
  return replaceGroupMarks(paths, groups);
}, "splitRoutingPath");
var extractGroupsFromPath = /* @__PURE__ */ __name((path) => {
  const groups = [];
  path = path.replace(/\{[^}]+\}/g, (match2, index) => {
    const mark = `@${index}`;
    groups.push([mark, match2]);
    return mark;
  });
  return {
    groups,
    path
  };
}, "extractGroupsFromPath");
var replaceGroupMarks = /* @__PURE__ */ __name((paths, groups) => {
  for (let i = groups.length - 1; i >= 0; i--) {
    const [mark] = groups[i];
    for (let j = paths.length - 1; j >= 0; j--) if (paths[j].includes(mark)) {
      paths[j] = paths[j].replace(mark, groups[i][1]);
      break;
    }
  }
  return paths;
}, "replaceGroupMarks");
var patternCache = {};
var getPattern = /* @__PURE__ */ __name((label, next) => {
  if (label === "*") return "*";
  const match2 = label.match(/^\:([^\{\}]+)(?:\{(.+)\})?$/);
  if (match2) {
    const cacheKey = `${label}#${next}`;
    if (!patternCache[cacheKey]) {
      if (match2[2]) patternCache[cacheKey] = next && next[0] !== ":" && next[0] !== "*" ? [
        cacheKey,
        match2[1],
        new RegExp(`^(?:${match2[2]})(?=/${next})`)
      ] : [
        label,
        match2[1],
        new RegExp(`^(?:${match2[2]})$`)
      ];
      else patternCache[cacheKey] = [
        label,
        match2[1],
        true
      ];
    }
    return patternCache[cacheKey];
  }
  return null;
}, "getPattern");
var tryDecode = /* @__PURE__ */ __name((str2, decoder) => {
  try {
    return decoder(str2);
  } catch {
    return str2.replace(/(?:%[0-9A-Fa-f]{2})+/g, (match2) => {
      try {
        return decoder(match2);
      } catch {
        return match2;
      }
    });
  }
}, "tryDecode");
var decodeURIWithPreservedPercent = /* @__PURE__ */ __name((value) => decodeURI(value.includes("%25") ? value.replace(/%25/g, "%2525") : value), "decodeURIWithPreservedPercent");
var getPath = /* @__PURE__ */ __name((request) => {
  const url = request.url;
  const start = url.charCodeAt(0) === 47 ? 0 : url.indexOf("/", url.indexOf(":") + 4);
  let i = start;
  for (; i < url.length; i++) {
    const charCode = url.charCodeAt(i);
    if (charCode === 37) {
      const queryIndex = url.indexOf("?", i);
      const hashIndex = url.indexOf("#", i);
      const end = queryIndex === -1 ? hashIndex === -1 ? void 0 : hashIndex : hashIndex === -1 ? queryIndex : Math.min(queryIndex, hashIndex);
      const path = url.slice(start, end);
      const decoded = tryDecode(path, decodeURIWithPreservedPercent);
      if (/%(?![0-9A-Fa-f]{2})/.test(path)) {
        const rewritten = new URL("http://localhost");
        rewritten.pathname = decoded.replace(/[\\\t\n\r]/g, encodeURIComponent);
        if (tryDecode(rewritten.pathname, decodeURIWithPreservedPercent) !== decoded) return tryDecode(path.replace(/%(?![0-9A-Fa-f]{2})/g, "%25"), decodeURIWithPreservedPercent);
      }
      return decoded;
    } else if (charCode === 63 || charCode === 35) break;
  }
  return url.slice(start, i);
}, "getPath");
var getPathNoStrict = /* @__PURE__ */ __name((request) => {
  const result = getPath(request);
  return result.length > 1 && result.at(-1) === "/" ? result.slice(0, -1) : result;
}, "getPathNoStrict");
var mergePath = /* @__PURE__ */ __name((base, sub, ...rest) => {
  if (rest.length) sub = mergePath(sub, ...rest);
  return `${base?.[0] === "/" ? "" : "/"}${base}${sub === "/" ? "" : `${base?.at(-1) === "/" ? "" : "/"}${sub?.[0] === "/" ? sub.slice(1) : sub}`}`;
}, "mergePath");
var checkOptionalParameter = /* @__PURE__ */ __name((path) => {
  if (path.charCodeAt(path.length - 1) !== 63 || !path.includes(":")) return null;
  const segments = path.split("/");
  const results = [];
  let basePath = "";
  segments.forEach((segment) => {
    if (segment !== "" && !/\:/.test(segment)) basePath += "/" + segment;
    else if (/\:/.test(segment)) {
      if (segment.charCodeAt(segment.length - 1) === 63) {
        if (results.length === 0 && basePath === "") results.push("/");
        else results.push(basePath);
        const optionalSegment = segment.slice(0, -1);
        basePath += "/" + optionalSegment;
        results.push(basePath);
      } else basePath += "/" + segment;
    }
  });
  return results.filter((v, i, a) => a.indexOf(v) === i);
}, "checkOptionalParameter");
var tryDecodeURIComponent = /* @__PURE__ */ __name((str2) => str2.indexOf("%") !== -1 ? tryDecode(str2, decodeURIComponent_) : str2, "tryDecodeURIComponent");
var _decodeURI = /* @__PURE__ */ __name((value) => {
  if (value.indexOf("+") !== -1) value = value.replace(/\+/g, " ");
  return tryDecodeURIComponent(value);
}, "_decodeURI");
var _getQueryParam = /* @__PURE__ */ __name((url, key, multiple) => {
  const hashIndex = url.indexOf("#", 8);
  if (hashIndex !== -1) url = url.slice(0, hashIndex);
  let encoded;
  if (!multiple && key && !/[%+&=]/.test(key)) {
    const queryIndex = url.indexOf("?", 8);
    let keyIndex2 = queryIndex;
    if (keyIndex2 === -1) return;
    if (!url.startsWith(key, keyIndex2 + 1)) keyIndex2 = url.indexOf(`&${key}`, keyIndex2 + 1);
    while (keyIndex2 !== -1) {
      const trailingKeyCode = url.charCodeAt(keyIndex2 + key.length + 1);
      if (trailingKeyCode === 61 || trailingKeyCode === 38 || isNaN(trailingKeyCode)) {
        if (keyIndex2 > queryIndex && /(?:^|&)[^=&]*[%+]/.test(url.slice(queryIndex + 1, keyIndex2))) break;
        if (trailingKeyCode === 61) {
          const valueIndex = keyIndex2 + key.length + 2;
          const endIndex = url.indexOf("&", valueIndex);
          return _decodeURI(url.slice(valueIndex, endIndex === -1 ? void 0 : endIndex));
        }
        return "";
      }
      keyIndex2 = url.indexOf(`&${key}`, keyIndex2 + 1);
    }
    encoded = /[%+]/.test(url);
    if (!encoded) return;
  }
  const results = /* @__PURE__ */ Object.create(null);
  encoded ??= /[%+]/.test(url);
  let keyIndex = url.indexOf("?", 8);
  while (keyIndex !== -1) {
    const nextKeyIndex = url.indexOf("&", keyIndex + 1);
    let valueIndex = url.indexOf("=", keyIndex);
    if (valueIndex > nextKeyIndex && nextKeyIndex !== -1) valueIndex = -1;
    let name = url.slice(keyIndex + 1, valueIndex === -1 ? nextKeyIndex === -1 ? void 0 : nextKeyIndex : valueIndex);
    if (encoded) name = _decodeURI(name);
    keyIndex = nextKeyIndex;
    if (name === "") continue;
    let value;
    if (valueIndex === -1) value = "";
    else {
      value = url.slice(valueIndex + 1, nextKeyIndex === -1 ? void 0 : nextKeyIndex);
      if (encoded) value = _decodeURI(value);
    }
    if (multiple) {
      if (!(results[name] && Array.isArray(results[name]))) results[name] = [];
      results[name].push(value);
    } else results[name] ??= value;
  }
  return key ? results[key] : results;
}, "_getQueryParam");
var getQueryParam = _getQueryParam;
var getQueryParams = /* @__PURE__ */ __name((url, key) => {
  return _getQueryParam(url, key, true);
}, "getQueryParams");
var decodeURIComponent_ = decodeURIComponent;

// ../../../workspace/worker/node_modules/hono/dist/request.js
var HonoRequest = class {
  static {
    __name(this, "HonoRequest");
  }
  /**
  * `.raw` can get the raw Request object.
  *
  * @see {@link https://hono.dev/docs/api/request#raw}
  *
  * @example
  * ```ts
  * // For Cloudflare Workers
  * app.post('/', async (c) => {
  *   const metadata = c.req.raw.cf?.hostMetadata?
  *   ...
  * })
  * ```
  */
  raw;
  #validatedData;
  #matchResult;
  routeIndex = 0;
  /**
  * `.path` can get the pathname of the request.
  *
  * @see {@link https://hono.dev/docs/api/request#path}
  *
  * @example
  * ```ts
  * app.get('/about/me', (c) => {
  *   const pathname = c.req.path // `/about/me`
  * })
  * ```
  */
  path;
  bodyCache = {};
  constructor(request, path = "/", matchResult = [[]]) {
    this.raw = request;
    this.path = path;
    this.#matchResult = matchResult;
  }
  param(key) {
    return key ? this.#getDecodedParam(key) : this.#getAllDecodedParams();
  }
  #getDecodedParam(key) {
    const paramKey = this.#matchResult[0][this.routeIndex]?.[1][key];
    const param = this.#getParamValue(paramKey);
    return param && tryDecodeURIComponent(param);
  }
  #getAllDecodedParams() {
    const decoded = {};
    const keys = Object.keys(this.#matchResult[0][this.routeIndex]?.[1] ?? {});
    for (const key of keys) {
      const value = this.#getParamValue(this.#matchResult[0][this.routeIndex][1][key]);
      if (value !== void 0) decoded[key] = tryDecodeURIComponent(value);
    }
    return decoded;
  }
  #getParamValue(paramKey) {
    return this.#matchResult[1] ? this.#matchResult[1][paramKey] : paramKey;
  }
  query(key) {
    return getQueryParam(this.url, key);
  }
  queries(key) {
    return getQueryParams(this.url, key);
  }
  header(name) {
    if (name) return this.raw.headers.get(name) ?? void 0;
    const headerData = /* @__PURE__ */ Object.create(null);
    this.raw.headers.forEach((value, key) => {
      headerData[key] = value;
    });
    return headerData;
  }
  async parseBody(options) {
    return parseBody(this, options);
  }
  #cachedBody = /* @__PURE__ */ __name((key) => {
    const { bodyCache, raw: raw2 } = this;
    const cachedBody = bodyCache[key];
    if (cachedBody) return cachedBody;
    for (const anyCachedKey in bodyCache) return bodyCache[anyCachedKey].then((body) => {
      if (anyCachedKey === "json") body = JSON.stringify(body);
      const contentType = anyCachedKey === "formData" ? void 0 : raw2.headers.get("content-type");
      return new Response(body, { headers: contentType ? { "Content-Type": contentType } : void 0 })[key]();
    });
    return bodyCache[key] = raw2[key]();
  }, "#cachedBody");
  /**
  * `.json()` can parse Request body of type `application/json`
  *
  * @see {@link https://hono.dev/docs/api/request#json}
  *
  * @example
  * ```ts
  * app.post('/entry', async (c) => {
  *   const body = await c.req.json()
  * })
  * ```
  */
  json() {
    return this.#cachedBody("text").then((text2) => JSON.parse(text2));
  }
  /**
  * `.text()` can parse Request body of type `text/plain`
  *
  * @see {@link https://hono.dev/docs/api/request#text}
  *
  * @example
  * ```ts
  * app.post('/entry', async (c) => {
  *   const body = await c.req.text()
  * })
  * ```
  */
  text() {
    return this.#cachedBody("text");
  }
  /**
  * `.arrayBuffer()` parse Request body as an `ArrayBuffer`
  *
  * @see {@link https://hono.dev/docs/api/request#arraybuffer}
  *
  * @example
  * ```ts
  * app.post('/entry', async (c) => {
  *   const body = await c.req.arrayBuffer()
  * })
  * ```
  */
  arrayBuffer() {
    return this.#cachedBody("arrayBuffer");
  }
  /**
  * `.bytes()` parses the request body as a `Uint8Array`.
  *
  * @see {@link https://hono.dev/docs/api/request#bytes}
  *
  * @example
  * ```ts
  * app.post('/entry', async (c) => {
  *   const body = await c.req.bytes()
  * })
  * ```
  */
  bytes() {
    return this.#cachedBody("arrayBuffer").then((buffer) => new Uint8Array(buffer));
  }
  /**
  * Parses the request body as a `Blob`.
  * @example
  * ```ts
  * app.post('/entry', async (c) => {
  *   const body = await c.req.blob();
  * });
  * ```
  * @see https://hono.dev/docs/api/request#blob
  */
  blob() {
    return this.#cachedBody("blob");
  }
  /**
  * Parses the request body as `FormData`.
  * @example
  * ```ts
  * app.post('/entry', async (c) => {
  *   const body = await c.req.formData();
  * });
  * ```
  * @see https://hono.dev/docs/api/request#formdata
  */
  formData() {
    return this.#cachedBody("formData");
  }
  /**
  * Adds validated data to the request.
  *
  * @param target - The target of the validation.
  * @param data - The validated data to add.
  */
  addValidatedData(target, data) {
    (this.#validatedData ??= {})[target] = data;
  }
  valid(target) {
    return this.#validatedData?.[target];
  }
  /**
  * `.url` can get the request url strings.
  *
  * @see {@link https://hono.dev/docs/api/request#url}
  *
  * @example
  * ```ts
  * app.get('/about/me', (c) => {
  *   const url = c.req.url // `http://localhost:8787/about/me`
  *   ...
  * })
  * ```
  */
  get url() {
    return this.raw.url;
  }
  /**
  * `.method` can get the method name of the request.
  *
  * @see {@link https://hono.dev/docs/api/request#method}
  *
  * @example
  * ```ts
  * app.get('/about/me', (c) => {
  *   const method = c.req.method // `GET`
  * })
  * ```
  */
  get method() {
    return this.raw.method;
  }
  get [GET_MATCH_RESULT]() {
    return this.#matchResult;
  }
  /**
  * `.matchedRoutes` can return a matched route in the handler
  *
  * @deprecated
  *
  * Use matchedRoutes helper defined in "hono/route" instead.
  *
  * @see {@link https://hono.dev/docs/api/request#matchedroutes}
  *
  * @example
  * ```ts
  * app.use('*', async function logger(c, next) {
  *   await next()
  *   c.req.matchedRoutes.forEach(({ handler, method, path }, i) => {
  *     const name = handler.name || (handler.length < 2 ? '[handler]' : '[middleware]')
  *     console.log(
  *       method,
  *       ' ',
  *       path,
  *       ' '.repeat(Math.max(10 - path.length, 0)),
  *       name,
  *       i === c.req.routeIndex ? '<- respond from here' : ''
  *     )
  *   })
  * })
  * ```
  */
  get matchedRoutes() {
    return this.#matchResult[0].map(([[, route]]) => route);
  }
  /**
  * `.routePath` can retrieve the path registered within the handler
  *
  * @deprecated
  *
  * Use routePath helper defined in "hono/route" instead.
  *
  * @see {@link https://hono.dev/docs/api/request#routepath}
  *
  * @example
  * ```ts
  * app.get('/posts/:id', (c) => {
  *   return c.json({ path: c.req.routePath })
  * })
  * ```
  */
  get routePath() {
    return this.#matchResult[0].map(([[, route]]) => route)[this.routeIndex].path;
  }
};

// ../../../workspace/worker/node_modules/hono/dist/utils/html.js
var HtmlEscapedCallbackPhase = {
  Stringify: 1,
  BeforeStream: 2,
  Stream: 3
};
var raw = /* @__PURE__ */ __name((value, callbacks) => {
  const escapedString = new String(value);
  escapedString.isEscaped = true;
  escapedString.callbacks = callbacks;
  return escapedString;
}, "raw");
var resolveCallback = /* @__PURE__ */ __name(async (str2, phase, preserveCallbacks, context, buffer) => {
  if (typeof str2 === "object" && !(str2 instanceof String)) {
    if (!(str2 instanceof Promise)) str2 = str2.toString();
    if (str2 instanceof Promise) str2 = await str2;
  }
  const callbacks = str2.callbacks;
  if (!callbacks?.length) return Promise.resolve(str2);
  if (buffer) buffer[0] += str2;
  else buffer = [str2];
  const resStr = Promise.all(callbacks.map((c) => c({
    phase,
    buffer,
    context
  }))).then((res) => Promise.all(res.filter(Boolean).map((str3) => resolveCallback(str3, phase, false, context, buffer))).then(() => buffer[0]));
  if (preserveCallbacks) return raw(await resStr, callbacks);
  else return resStr;
}, "resolveCallback");

// ../../../workspace/worker/node_modules/hono/dist/context.js
var TEXT_PLAIN = "text/plain; charset=UTF-8";
var setDefaultContentType = /* @__PURE__ */ __name((contentType, headers) => {
  return {
    "Content-Type": contentType,
    ...headers
  };
}, "setDefaultContentType");
var createResponseInstance = /* @__PURE__ */ __name((body, init) => new Response(body, init), "createResponseInstance");
var Context = class {
  static {
    __name(this, "Context");
  }
  #rawRequest;
  #req;
  /**
  * `.env` can get bindings (environment variables, secrets, KV namespaces, D1 database, R2 bucket etc.) in Cloudflare Workers.
  *
  * @see {@link https://hono.dev/docs/api/context#env}
  *
  * @example
  * ```ts
  * // Environment object for Cloudflare Workers
  * app.get('*', async c => {
  *   const counter = c.env.COUNTER
  * })
  * ```
  */
  env = {};
  #var;
  finalized = false;
  /**
  * `.error` can get the error object from the middleware if the Handler throws an error.
  *
  * @see {@link https://hono.dev/docs/api/context#error}
  *
  * @example
  * ```ts
  * app.use('*', async (c, next) => {
  *   await next()
  *   if (c.error) {
  *     // do something...
  *   }
  * })
  * ```
  */
  error;
  #status;
  #executionCtx;
  #res;
  #layout;
  #renderer;
  #notFoundHandler;
  #preparedHeaders;
  #matchResult;
  #path;
  /**
  * Creates an instance of the Context class.
  *
  * @param req - The Request object.
  * @param options - Optional configuration options for the context.
  */
  constructor(req, options) {
    this.#rawRequest = req;
    if (options) {
      this.#executionCtx = options.executionCtx;
      this.env = options.env;
      this.#notFoundHandler = options.notFoundHandler;
      this.#path = options.path;
      this.#matchResult = options.matchResult;
    }
  }
  /**
  * `.req` is the instance of {@link HonoRequest}.
  */
  get req() {
    this.#req ??= new HonoRequest(this.#rawRequest, this.#path, this.#matchResult);
    return this.#req;
  }
  /**
  * @see {@link https://hono.dev/docs/api/context#event}
  * The FetchEvent associated with the current request.
  *
  * @throws Will throw an error if the context does not have a FetchEvent.
  */
  get event() {
    if (this.#executionCtx && "respondWith" in this.#executionCtx) return this.#executionCtx;
    else throw Error("This context has no FetchEvent");
  }
  /**
  * @see {@link https://hono.dev/docs/api/context#executionctx}
  * The ExecutionContext associated with the current request.
  *
  * @throws Will throw an error if the context does not have an ExecutionContext.
  */
  get executionCtx() {
    if (this.#executionCtx) return this.#executionCtx;
    else throw Error("This context has no ExecutionContext");
  }
  /**
  * @see {@link https://hono.dev/docs/api/context#res}
  * The Response object for the current request.
  */
  get res() {
    return this.#res ||= createResponseInstance(null, { headers: this.#preparedHeaders ??= new Headers() });
  }
  /**
  * Sets the Response object for the current request.
  *
  * @param _res - The Response object to set.
  */
  set res(_res) {
    if (this.#res && _res) {
      _res = createResponseInstance(_res.body, _res);
      for (const [k, v] of this.#res.headers.entries()) {
        if (k === "content-type") continue;
        if (k === "set-cookie") {
          const cookies = this.#res.headers.getSetCookie();
          _res.headers.delete("set-cookie");
          for (const cookie of cookies) _res.headers.append("set-cookie", cookie);
        } else _res.headers.set(k, v);
      }
    }
    this.#res = _res;
    this.finalized = true;
  }
  /**
  * `.render()` can create a response within a layout.
  *
  * @see {@link https://hono.dev/docs/api/context#render-setrenderer}
  *
  * @example
  * ```ts
  * app.get('/', (c) => {
  *   return c.render('Hello!')
  * })
  * ```
  */
  render = /* @__PURE__ */ __name((...args) => {
    this.#renderer ??= (content) => this.html(content);
    return this.#renderer(...args);
  }, "render");
  /**
  * Sets the layout for the response.
  *
  * @param layout - The layout to set.
  * @returns The layout function.
  */
  setLayout = /* @__PURE__ */ __name((layout) => this.#layout = layout, "setLayout");
  /**
  * Gets the current layout for the response.
  *
  * @returns The current layout function.
  */
  getLayout = /* @__PURE__ */ __name(() => this.#layout, "getLayout");
  /**
  * `.setRenderer()` can set the layout in the custom middleware.
  *
  * @see {@link https://hono.dev/docs/api/context#render-setrenderer}
  *
  * @example
  * ```tsx
  * app.use('*', async (c, next) => {
  *   c.setRenderer((content) => {
  *     return c.html(
  *       <html>
  *         <body>
  *           <p>{content}</p>
  *         </body>
  *       </html>
  *     )
  *   })
  *   await next()
  * })
  * ```
  */
  setRenderer = /* @__PURE__ */ __name((renderer) => {
    this.#renderer = renderer;
  }, "setRenderer");
  /**
  * `.header()` can set headers.
  *
  * @see {@link https://hono.dev/docs/api/context#header}
  *
  * @example
  * ```ts
  * app.get('/welcome', (c) => {
  *   // Set headers
  *   c.header('X-Message', 'Hello!')
  *   c.header('Content-Type', 'text/plain')
  *
  *   // Append multiple headers using the append option (e.g. Vary)
  *   c.header('Vary', 'Accept-Encoding', { append: true })
  *   c.header('Vary', 'User-Agent', { append: true })
  *
  *   return c.body('Thank you for coming')
  * })
  * ```
  */
  header = /* @__PURE__ */ __name((name, value, options) => {
    if (this.finalized && !this.#res.bodyUsed) this.#res = createResponseInstance(this.#res.body, this.#res);
    const headers = this.#res ? this.#res.headers : this.#preparedHeaders ??= new Headers();
    if (value === void 0) headers.delete(name);
    else if (options?.append) headers.append(name, value);
    else headers.set(name, value);
  }, "header");
  status = /* @__PURE__ */ __name((status) => {
    this.#status = status;
  }, "status");
  /**
  * `.set()` can set the value specified by the key.
  *
  * @see {@link https://hono.dev/docs/api/context#set-get}
  *
  * @example
  * ```ts
  * app.use('*', async (c, next) => {
  *   c.set('message', 'Hono is hot!!')
  *   await next()
  * })
  * ```
  */
  set = /* @__PURE__ */ __name((key, value) => {
    this.#var ??= /* @__PURE__ */ new Map();
    this.#var.set(key, value);
  }, "set");
  /**
  * `.get()` can use the value specified by the key.
  *
  * @see {@link https://hono.dev/docs/api/context#set-get}
  *
  * @example
  * ```ts
  * app.get('/', (c) => {
  *   const message = c.get('message')
  *   return c.text(`The message is "${message}"`)
  * })
  * ```
  */
  get = /* @__PURE__ */ __name((key) => {
    return this.#var ? this.#var.get(key) : void 0;
  }, "get");
  /**
  * `.var` can access the value of a variable.
  *
  * @see {@link https://hono.dev/docs/api/context#var}
  *
  * @example
  * ```ts
  * const result = c.var.client.oneMethod()
  * ```
  */
  get var() {
    if (!this.#var) return {};
    return Object.fromEntries(this.#var);
  }
  #newResponse(data, arg, headers) {
    let responseHeaders = this.#res ? new Headers(this.#res.headers) : this.#preparedHeaders;
    if (typeof arg === "object" && arg.headers) {
      responseHeaders ??= new Headers();
      for (const [key, value] of new Headers(arg.headers)) if (key === "set-cookie") responseHeaders.append(key, value);
      else responseHeaders.set(key, value);
    }
    if (headers) {
      if (!responseHeaders) {
        let count = 0;
        for (const k in headers) if (++count > 1 || typeof headers[k] !== "string") {
          responseHeaders = new Headers();
          break;
        }
      }
      if (responseHeaders) for (const k in headers) {
        const v = headers[k];
        if (typeof v === "string") responseHeaders.set(k, v);
        else {
          responseHeaders.delete(k);
          for (const v2 of v) responseHeaders.append(k, v2);
        }
      }
    }
    const status = typeof arg === "number" ? arg : arg?.status ?? this.#status;
    return createResponseInstance(data, {
      status,
      headers: responseHeaders ?? headers
    });
  }
  newResponse = /* @__PURE__ */ __name((...args) => this.#newResponse(...args), "newResponse");
  /**
  * `.body()` can return the HTTP response.
  * You can set headers with `.header()` and set HTTP status code with `.status`.
  * This can also be set in `.text()`, `.json()` and so on.
  *
  * @see {@link https://hono.dev/docs/api/context#body}
  *
  * @example
  * ```ts
  * app.get('/welcome', (c) => {
  *   // Set headers
  *   c.header('X-Message', 'Hello!')
  *   c.header('Content-Type', 'text/plain')
  *   // Set HTTP status code
  *   c.status(201)
  *
  *   // Return the response body
  *   return c.body('Thank you for coming')
  * })
  * ```
  */
  body = /* @__PURE__ */ __name((data, arg, headers) => this.#newResponse(data, arg, headers), "body");
  /**
  * `.text()` can render text as `Content-Type:text/plain`.
  *
  * @see {@link https://hono.dev/docs/api/context#text}
  *
  * @example
  * ```ts
  * app.get('/say', (c) => {
  *   return c.text('Hello!')
  * })
  * ```
  */
  text = /* @__PURE__ */ __name((text2, arg, headers) => {
    return !this.#preparedHeaders && !this.#status && !arg && !headers && !this.finalized ? new Response(text2) : this.#newResponse(text2, arg, setDefaultContentType(TEXT_PLAIN, headers));
  }, "text");
  /**
  * `.json()` can render JSON as `Content-Type:application/json`.
  *
  * @see {@link https://hono.dev/docs/api/context#json}
  *
  * @example
  * ```ts
  * app.get('/api', (c) => {
  *   return c.json({ message: 'Hello!' })
  * })
  * ```
  */
  json = /* @__PURE__ */ __name((object, arg, headers) => {
    return this.#newResponse(JSON.stringify(object), arg, setDefaultContentType("application/json", headers));
  }, "json");
  html = /* @__PURE__ */ __name((html, arg, headers) => {
    const res = /* @__PURE__ */ __name((html2) => this.#newResponse(html2, arg, setDefaultContentType("text/html; charset=UTF-8", headers)), "res");
    return typeof html === "object" ? resolveCallback(html, HtmlEscapedCallbackPhase.Stringify, false, {}).then(res) : res(html);
  }, "html");
  /**
  * `.redirect()` can Redirect, default status code is 302.
  *
  * @see {@link https://hono.dev/docs/api/context#redirect}
  *
  * @example
  * ```ts
  * app.get('/redirect', (c) => {
  *   return c.redirect('/')
  * })
  * app.get('/redirect-permanently', (c) => {
  *   return c.redirect('/', 301)
  * })
  * ```
  */
  redirect = /* @__PURE__ */ __name((location, status) => {
    const locationString = String(location);
    this.header("Location", !/[^\x00-\xFF]/.test(locationString) ? locationString : encodeURI(locationString));
    return this.newResponse(null, status ?? 302);
  }, "redirect");
  /**
  * `.notFound()` can return the Not Found Response.
  *
  * @see {@link https://hono.dev/docs/api/context#notfound}
  *
  * @example
  * ```ts
  * app.get('/notfound', (c) => {
  *   return c.notFound()
  * })
  * ```
  */
  notFound = /* @__PURE__ */ __name(() => {
    this.#notFoundHandler ??= () => createResponseInstance();
    return this.#notFoundHandler(this);
  }, "notFound");
};

// ../../../workspace/worker/node_modules/hono/dist/compose.js
var compose = /* @__PURE__ */ __name((middleware, onError, onNotFound) => {
  return (context, next) => {
    let index = -1;
    return dispatch(0);
    async function dispatch(i) {
      if (i <= index) throw new Error("next() called multiple times");
      index = i;
      let res;
      let isError = false;
      let handler;
      if (middleware[i]) {
        handler = middleware[i][0][0];
        context.req.routeIndex = i;
      } else handler = i === middleware.length && next || void 0;
      if (handler) try {
        res = await handler(context, () => dispatch(i + 1));
      } catch (err) {
        if (err instanceof Error && onError) {
          context.error = err;
          res = await onError(err, context);
          isError = true;
        } else throw err;
      }
      else if (context.finalized === false && onNotFound) res = await onNotFound(context);
      if (res && (context.finalized === false || isError)) context.res = res;
      return context;
    }
    __name(dispatch, "dispatch");
  };
}, "compose");

// ../../../workspace/worker/node_modules/hono/dist/helper/route/index.js
var matchedRoutes = /* @__PURE__ */ __name((c) => c.req[GET_MATCH_RESULT][0].map(([[, route]]) => route), "matchedRoutes");
var routePath = /* @__PURE__ */ __name((c, index) => matchedRoutes(c).at(index ?? c.req.routeIndex)?.path ?? "", "routePath");

// ../../../workspace/worker/node_modules/hono/dist/router.js
var METHODS = [
  "get",
  "post",
  "put",
  "delete",
  "options",
  "patch",
  "query"
];
var MESSAGE_MATCHER_IS_ALREADY_BUILT = "Can not add a route since the matcher is already built.";
var UnsupportedPathError = class extends Error {
  static {
    __name(this, "UnsupportedPathError");
  }
};

// ../../../workspace/worker/node_modules/hono/dist/utils/constants.js
var COMPOSED_HANDLER = "__COMPOSED_HANDLER";

// ../../../workspace/worker/node_modules/hono/dist/utils/mount.js
var countTrailingSlashes = /* @__PURE__ */ __name((path) => {
  let index = path.length;
  while (index > 0 && path.charCodeAt(index - 1) === 47) index--;
  return path.length - index;
}, "countTrailingSlashes");
var getPathPrefixLength = /* @__PURE__ */ __name((c, pathPrefix, routePath2) => {
  if (!/[:*]/.test(pathPrefix)) return pathPrefix.length;
  const path = c.req.path;
  const matchResult = c.req[GET_MATCH_RESULT];
  const paramNames = /* @__PURE__ */ new Set();
  let length = 0;
  for (const part of splitRoutingPath(pathPrefix)) {
    if (part[0] === ":" && part.endsWith("}?")) throw new Error(`mount(): Optional regular expression parameters are not supported in "${routePath2}".`);
    const pattern = getPattern(part);
    if (pattern && pattern !== "*") {
      const name = pattern[1];
      if (paramNames.has(name)) throw new Error(`mount(): Duplicate path parameter "${name}" in "${routePath2}".`);
      paramNames.add(name);
    }
    if (pattern && pattern !== "*" && pattern[2] !== true) {
      const value = matchResult.length === 2 ? matchResult[1][matchResult[0][c.req.routeIndex][1][pattern[1]]] : matchResult[0][c.req.routeIndex][1][pattern[1]];
      length += value.length + 1;
    } else if (pattern || part.endsWith("*")) {
      const end = path.indexOf("/", length + 1);
      length = end === -1 ? path.length : end;
    } else length += part.length + 1;
  }
  return length;
}, "getPathPrefixLength");
var createMountedRequest = /* @__PURE__ */ __name((c, pathPrefix, routePath2) => {
  if (/[^/]\*$/.test(routePath2)) throw new Error(`mount(): Wildcard must follow "/" in "${routePath2}".`);
  const prefixLength = getPathPrefixLength(c, pathPrefix, routePath2);
  const path = c.req.path.slice(prefixLength) || "/";
  if (prefixLength > c.req.path.length || path[0] !== "/" || /\/(?:\.|%2e){1,2}(?:\/|$)/i.test(path)) throw new HTTPException(400, { message: "Invalid mounted path" });
  const rawUrl = c.req.raw.url;
  if (/^[^/?#]*\/\/[^/?#\\]*[?#\\]/.test(rawUrl)) throw new HTTPException(400, { message: "Invalid mounted path" });
  const rawPathEnd = rawUrl.search(/[?#]/);
  const rawTrailingSlashes = countTrailingSlashes(rawPathEnd === -1 ? rawUrl : rawUrl.slice(0, rawPathEnd));
  if (rawTrailingSlashes > 1 && countTrailingSlashes(c.req.path) === rawTrailingSlashes - 1) throw new HTTPException(400, { message: "Invalid mounted path" });
  const url = new URL(rawUrl);
  url.pathname = path.replace(/[\\\t\n\r]/g, encodeURIComponent);
  if (path.includes("%")) {
    let decoded;
    try {
      decoded = decodeURI(path);
    } catch {
    }
    if (decoded === void 0) {
      if (tryDecode(url.pathname, (value) => decodeURI(value.replace(/%25/g, "%2525"))) !== path) throw new HTTPException(400, { message: "Invalid mounted path" });
    }
  }
  return new Request(url, c.req.raw);
}, "createMountedRequest");

// ../../../workspace/worker/node_modules/hono/dist/hono-base.js
var notFoundHandler = /* @__PURE__ */ __name((c) => {
  return c.text("404 Not Found", 404);
}, "notFoundHandler");
var errorHandler = /* @__PURE__ */ __name((err, c) => {
  if ("getResponse" in err) {
    const res = err.getResponse();
    return c.newResponse(res.body, res);
  }
  console.error(err);
  return c.text("Internal Server Error", 500);
}, "errorHandler");
var Hono = class Hono2 {
  static {
    __name(this, "Hono");
  }
  get;
  post;
  put;
  delete;
  options;
  patch;
  query;
  all;
  on;
  use;
  router;
  getPath;
  _basePath = "/";
  #path = "/";
  routes = [];
  constructor(options = {}) {
    [...METHODS, "all"].forEach((method) => {
      this[method] = (args1, ...args) => {
        const methodName = method.toUpperCase();
        if (typeof args1 === "string") this.#path = args1;
        else this.#addRoute(methodName, this.#path, args1);
        args.forEach((handler) => {
          this.#addRoute(methodName, this.#path, handler);
        });
        return this;
      };
    });
    this.on = (method, path, ...handlers) => {
      for (const p of [path].flat()) {
        this.#path = p;
        for (const m of [method].flat()) {
          const methodName = m.toUpperCase();
          for (const handler of handlers) this.#addRoute(methodName, this.#path, handler);
        }
      }
      return this;
    };
    this.use = (arg1, ...handlers) => {
      if (typeof arg1 === "string") this.#path = arg1;
      else {
        this.#path = "*";
        handlers.unshift(arg1);
      }
      handlers.forEach((handler) => {
        this.#addRoute("ALL", this.#path, handler);
      });
      return this;
    };
    const { strict, ...optionsWithoutStrict } = options;
    Object.assign(this, optionsWithoutStrict);
    this.getPath = strict ?? true ? options.getPath ?? getPath : getPathNoStrict;
  }
  #clone() {
    const clone = new Hono2({
      router: this.router,
      getPath: this.getPath
    });
    clone.errorHandler = this.errorHandler;
    clone.#notFoundHandler = this.#notFoundHandler;
    clone.routes = this.routes;
    return clone;
  }
  #notFoundHandler = notFoundHandler;
  errorHandler = errorHandler;
  /**
  * `.route()` allows grouping other Hono instance in routes.
  *
  * @see {@link https://hono.dev/docs/api/routing#grouping}
  *
  * @param {string} path - base Path
  * @param {Hono} app - other Hono instance
  * @returns {Hono} routed Hono instance
  *
  * @example
  * ```ts
  * const app = new Hono()
  * const app2 = new Hono()
  *
  * app2.get("/user", (c) => c.text("user"))
  * app.route("/api", app2) // GET /api/user
  * ```
  */
  route(path, app2) {
    const subApp = this.basePath(path);
    app2.routes.map((r) => {
      let handler;
      if (app2.errorHandler === errorHandler) handler = r.handler;
      else {
        handler = /* @__PURE__ */ __name(async (c, next) => (await compose([], app2.errorHandler)(c, () => r.handler(c, next))).res, "handler");
        handler[COMPOSED_HANDLER] = r.handler;
      }
      subApp.#addRoute(r.method, r.path, handler, r.basePath);
    });
    return this;
  }
  /**
  * `.basePath()` allows base paths to be specified.
  *
  * @see {@link https://hono.dev/docs/api/routing#base-path}
  *
  * @param {string} path - base Path
  * @returns {Hono} changed Hono instance
  *
  * @example
  * ```ts
  * const api = new Hono().basePath('/api')
  * ```
  */
  basePath(path) {
    const subApp = this.#clone();
    subApp._basePath = mergePath(this._basePath, path);
    return subApp;
  }
  /**
  * `.onError()` handles an error and returns a customized Response.
  *
  * @see {@link https://hono.dev/docs/api/hono#error-handling}
  *
  * @param {ErrorHandler} handler - request Handler for error
  * @returns {Hono} changed Hono instance
  *
  * @example
  * ```ts
  * app.onError((err, c) => {
  *   console.error(`${err}`)
  *   return c.text('Custom Error Message', 500)
  * })
  * ```
  */
  onError = /* @__PURE__ */ __name((handler) => {
    this.errorHandler = handler;
    return this;
  }, "onError");
  /**
  * `.notFound()` allows you to customize a Not Found Response.
  *
  * @see {@link https://hono.dev/docs/api/hono#not-found}
  *
  * @param {NotFoundHandler} handler - request handler for not-found
  * @returns {Hono} changed Hono instance
  *
  * @example
  * ```ts
  * app.notFound((c) => {
  *   return c.text('Custom 404 Message', 404)
  * })
  * ```
  */
  notFound = /* @__PURE__ */ __name((handler) => {
    this.#notFoundHandler = handler;
    return this;
  }, "notFound");
  /**
  * `.mount()` allows you to mount applications built with other frameworks into your Hono application.
  *
  * @deprecated Use `mount()` from `hono/mount` instead. `.mount()` will be removed in v5.
  *
  * @see {@link https://hono.dev/docs/api/hono#mount}
  *
  * @param {string} path - base Path
  * @param {Function} applicationHandler - other Request Handler
  * @param {MountOptions} [options] - options of `.mount()`
  * @returns {Hono} mounted Hono instance
  * @throws {Error} If automatic request rewriting encounters duplicate path parameter names or an optional regular expression parameter.
  * @throws {HTTPException} With status 400 if automatic request rewriting cannot safely preserve the routed path.
  *
  * @example
  * ```ts
  * import { Router as IttyRouter } from 'itty-router'
  * import { Hono } from 'hono'
  * // Create itty-router application
  * const ittyRouter = IttyRouter()
  * // GET /itty-router/hello
  * ittyRouter.get('/hello', () => new Response('Hello from itty-router'))
  *
  * const app = new Hono()
  * app.mount('/itty-router', ittyRouter.handle)
  * ```
  *
  * @example
  * ```ts
  * const app = new Hono()
  * // Send the request to another application without modification.
  * app.mount('/app', anotherApp, {
  *   replaceRequest: (req) => req,
  * })
  * ```
  */
  mount(path, applicationHandler, options) {
    let replaceRequest;
    let optionHandler;
    if (options) {
      if (typeof options === "function") optionHandler = options;
      else {
        optionHandler = options.optionHandler;
        if (options.replaceRequest === false) replaceRequest = /* @__PURE__ */ __name((request) => request, "replaceRequest");
        else replaceRequest = options.replaceRequest;
      }
    }
    const getOptions = optionHandler ? (c) => {
      const options2 = optionHandler(c);
      return Array.isArray(options2) ? options2 : [options2];
    } : (c) => {
      let executionContext = void 0;
      try {
        executionContext = c.executionCtx;
      } catch {
      }
      return [c.env, executionContext];
    };
    const defaultReplaceRequest = /* @__PURE__ */ __name((c) => {
      const mountedRoutePath = routePath(c);
      return createMountedRequest(c, mountedRoutePath.replace(/\/?\*$/, ""), mountedRoutePath);
    }, "defaultReplaceRequest");
    const handler = /* @__PURE__ */ __name(async (c, next) => {
      const res = await applicationHandler(replaceRequest ? replaceRequest(c.req.raw) : defaultReplaceRequest(c), ...getOptions(c));
      if (res) return res;
      await next();
    }, "handler");
    this.#addRoute("ALL", mergePath(path, "*"), handler);
    return this;
  }
  #addRoute(method, path, handler, baseRoutePath) {
    path = mergePath(this._basePath, path);
    const r = {
      basePath: baseRoutePath !== void 0 ? mergePath(this._basePath, baseRoutePath) : this._basePath,
      path,
      method,
      handler
    };
    this.router.add(method, path, [handler, r]);
    this.routes.push(r);
  }
  #handleError(err, c) {
    if (err instanceof Error) return this.errorHandler(err, c);
    throw err;
  }
  #dispatch(request, executionCtx, env, method) {
    if (method === "HEAD") return (async () => new Response(null, await this.#dispatch(request, executionCtx, env, "GET")))();
    const path = this.getPath(request, { env });
    const matchResult = this.router.match(method, path);
    const c = new Context(request, {
      path,
      matchResult,
      env,
      executionCtx,
      notFoundHandler: this.#notFoundHandler
    });
    if (matchResult[0].length === 1) {
      let res;
      try {
        res = matchResult[0][0][0][0](c, async () => {
          c.res = await this.#notFoundHandler(c);
        });
      } catch (err) {
        return this.#handleError(err, c);
      }
      return res instanceof Promise ? res.then((resolved) => resolved || (c.finalized ? c.res : this.#notFoundHandler(c))).catch((err) => this.#handleError(err, c)) : res ?? this.#notFoundHandler(c);
    }
    const composed = compose(matchResult[0], this.errorHandler, this.#notFoundHandler);
    return (async () => {
      try {
        const context = await composed(c);
        if (!context.finalized) throw new Error("Context is not finalized. Did you forget to return a Response object or `await next()`?");
        return context.res;
      } catch (err) {
        return this.#handleError(err, c);
      }
    })();
  }
  /**
  * `.fetch()` will be entry point of your app.
  *
  * @see {@link https://hono.dev/docs/api/hono#fetch}
  *
  * @param {Request} request - request Object of request
  * @param {Env} env - env Object
  * @param {ExecutionContext} executionCtx - context of execution
  * @returns {Response | Promise<Response>} response of request
  *
  */
  fetch = /* @__PURE__ */ __name((request, ...rest) => {
    return this.#dispatch(request, rest[1], rest[0], request.method);
  }, "fetch");
  /**
  * `.request()` is a useful method for testing.
  * You can pass a URL or pathname to send a GET request.
  * app will return a Response object.
  * ```ts
  * test('GET /hello is ok', async () => {
  *   const res = await app.request('/hello')
  *   expect(res.status).toBe(200)
  * })
  * ```
  * @see https://hono.dev/docs/api/hono#request
  */
  request = /* @__PURE__ */ __name((input, requestInit, Env, executionCtx) => {
    if (input instanceof Request) return this.fetch(requestInit ? new Request(input, requestInit) : input, Env, executionCtx);
    input = input.toString();
    return this.fetch(new Request(/^https?:\/\//.test(input) ? input : `http://localhost${mergePath("/", input)}`, requestInit), Env, executionCtx);
  }, "request");
  /**
  * `.fire()` automatically adds a global fetch event listener.
  * This can be useful for environments that adhere to the Service Worker API, such as non-ES module Cloudflare Workers.
  * @deprecated
  * Use `fire` from `hono/service-worker` instead.
  * ```ts
  * import { Hono } from 'hono'
  * import { fire } from 'hono/service-worker'
  *
  * const app = new Hono()
  * // ...
  * fire(app)
  * ```
  * @see https://hono.dev/docs/api/hono#fire
  * @see https://developer.mozilla.org/en-US/docs/Web/API/Service_Worker_API
  * @see https://developers.cloudflare.com/workers/reference/migrate-to-module-workers/
  */
  fire = /* @__PURE__ */ __name(() => {
    addEventListener("fetch", (event) => {
      event.respondWith(this.#dispatch(event.request, event, void 0, event.request.method));
    });
  }, "fire");
};

// ../../../workspace/worker/node_modules/hono/dist/router/utils.js
var createNullObject = /* @__PURE__ */ __name(() => /* @__PURE__ */ Object.create(null), "createNullObject");

// ../../../workspace/worker/node_modules/hono/dist/router/reg-exp-router/matcher.js
var emptyParam = [];
function match(method, path) {
  const matchers = this.buildAllMatchers();
  const match2 = /* @__PURE__ */ __name(((method2, path2) => {
    const matcher = matchers[method2] || matchers["ALL"];
    const staticMatch = matcher[2][path2];
    if (staticMatch) return staticMatch;
    const match3 = path2.match(matcher[0]);
    if (!match3) return [[], emptyParam];
    const index = match3.indexOf("", 1);
    return [matcher[1][index], match3];
  }), "match");
  this.match = match2;
  return match2(method, path);
}
__name(match, "match");

// ../../../workspace/worker/node_modules/hono/dist/router/reg-exp-router/node.js
var LABEL_REG_EXP_STR = "[^/]+";
var ONLY_WILDCARD_REG_EXP_STR = "[^]*";
var TAIL_WILDCARD_REG_EXP_STR = "(?:|/[^]*)";
var PATH_ERROR = /* @__PURE__ */ Symbol();
var regExpMetaChars = /* @__PURE__ */ new Set(".\\+*[^]$()");
function compareKey(a, b) {
  if (a.length === 1) return b.length === 1 ? a < b ? -1 : 1 : -1;
  if (b.length === 1) return 1;
  if (a === "[^]*" || a === "(?:|/[^]*)") return b === "[^]*" ? -1 : 1;
  else if (b === "[^]*" || b === "(?:|/[^]*)") return -1;
  if (a === "[^/]+") return 1;
  else if (b === "[^/]+") return -1;
  return a.length === b.length ? a < b ? -1 : 1 : b.length - a.length;
}
__name(compareKey, "compareKey");
var Node = class Node2 {
  static {
    __name(this, "Node");
  }
  #index;
  #varIndex;
  #children = createNullObject();
  insert(tokens, index, paramMap, context, keys) {
    let node = this;
    for (let i = 0, len = tokens.length; i < len; i++) {
      const token2 = tokens[i];
      const pattern = token2.length === 1 ? token2 === "*" ? i === len - 1 ? [
        "",
        "",
        ONLY_WILDCARD_REG_EXP_STR
      ] : [
        "",
        "",
        LABEL_REG_EXP_STR
      ] : null : token2 === "/*" ? [
        "",
        "",
        TAIL_WILDCARD_REG_EXP_STR
      ] : token2.match(/^\:([^\{\}]+)(?:\{(.+)\})?$/);
      let nextNode;
      if (pattern) {
        const name = pattern[1];
        let regexpStr = pattern[2] || "[^/]+";
        if (name && pattern[2]) {
          if (new RegExp(regexpStr).test("")) throw PATH_ERROR;
          regexpStr = regexpStr.replace(/^\((?!\?:)(?=[^)]+\)$)/, "(?:");
          if (/\((?!\?:)/.test(regexpStr)) throw PATH_ERROR;
          if (regexpStr.length === 1 && regExpMetaChars.has(regexpStr)) throw PATH_ERROR;
        }
        keys.push(regexpStr);
        nextNode = node.#children[regexpStr];
        if (!nextNode) {
          if (regexpStr !== "[^]*" && regexpStr !== "(?:|/[^]*)") {
            for (const k in node.#children) if ((regexpStr.length > 1 || k.length > 1) && k !== "[^]*" && k !== "(?:|/[^]*)") throw PATH_ERROR;
          }
          nextNode = node.#children[regexpStr] = new Node2();
        }
        if (name !== "") {
          nextNode.#varIndex ??= context.varIndex++;
          paramMap.push([name, nextNode.#varIndex]);
        }
      } else {
        keys.push(token2);
        nextNode = node.#children[token2];
        if (!nextNode) {
          for (const k in node.#children) if (k.length > 1 && k !== "[^]*" && k !== "(?:|/[^]*)") throw PATH_ERROR;
          nextNode = node.#children[token2] = new Node2();
        }
      }
      node = nextNode;
    }
    if (node.#index !== void 0) throw PATH_ERROR;
    node.#index = index;
  }
  buildRegExpStr() {
    const strList = Object.keys(this.#children).sort(compareKey).map((k) => {
      const c = this.#children[k];
      const childStr = c.buildRegExpStr();
      return childStr === "" ? "" : (typeof c.#varIndex === "number" ? `(${k})@${c.#varIndex}` : regExpMetaChars.has(k) ? `\\${k}` : k) + childStr;
    }).filter(Boolean);
    if (typeof this.#index === "number" && this.#index !== -1) strList.unshift(`#${this.#index}`);
    if (strList.length === 0) return "";
    if (strList.length === 1) return strList[0];
    return "(?:" + strList.join("|") + ")";
  }
};

// ../../../workspace/worker/node_modules/hono/dist/router/reg-exp-router/trie.js
var Trie = class {
  static {
    __name(this, "Trie");
  }
  #context = { varIndex: 0 };
  #root = new Node();
  #index = 0;
  paths = createNullObject();
  insert(path, isStatic) {
    const keys = [];
    if (isStatic) {
      this.#root.insert(path.split(""), -1, [], this.#context, keys);
      this.paths[path] = [
        -1,
        [],
        keys
      ];
      return;
    }
    const paramAssoc = [];
    const groups = [];
    let markedPath = path;
    for (let i = 0; ; ) {
      let replaced = false;
      markedPath = markedPath.replace(/\{(?:\{[\d,]+\}|[^}])+\}/g, (m) => {
        const mark = `@\\${i}`;
        groups[i] = [mark, m];
        i++;
        replaced = true;
        return mark;
      });
      if (!replaced) break;
    }
    const tokens = markedPath.match(/(?::[^\/]+)|(?:\/\*$)|./gs) || [];
    for (let i = groups.length - 1; i >= 0; i--) {
      const [mark] = groups[i];
      for (let j = tokens.length - 1; j >= 0; j--) if (tokens[j].indexOf(mark) !== -1) {
        tokens[j] = tokens[j].replace(mark, groups[i][1]);
        break;
      }
    }
    this.#root.insert(tokens, this.#index, paramAssoc, this.#context, keys);
    this.paths[path] = [
      this.#index++,
      paramAssoc,
      keys
    ];
  }
  buildRegExp() {
    let regexp = this.#root.buildRegExpStr();
    if (regexp === "") return [
      /^$/,
      [],
      []
    ];
    let captureIndex = 0;
    const indexReplacementMap = [];
    const paramReplacementMap = [];
    regexp = regexp.replace(/#(\d+)|@(\d+)|\.\*\$/g, (_, handlerIndex, paramIndex) => {
      if (handlerIndex !== void 0) {
        indexReplacementMap[++captureIndex] = Number(handlerIndex);
        return "$()";
      }
      if (paramIndex !== void 0) {
        paramReplacementMap[Number(paramIndex)] = ++captureIndex;
        return "";
      }
      return "";
    });
    return [
      new RegExp(`^${regexp}`),
      indexReplacementMap,
      paramReplacementMap
    ];
  }
};

// ../../../workspace/worker/node_modules/hono/dist/router/reg-exp-router/router.js
function endsWithWildcard(keys) {
  const tail = keys[keys.length - 1];
  return tail === "[^]*" || tail === "(?:|/[^]*)";
}
__name(endsWithWildcard, "endsWithWildcard");
function covers(wildcard, target) {
  const last = wildcard.length - 1;
  for (let i = 0; i < last; i++) if (wildcard[i] !== target[i]) return false;
  return wildcard[last] === "[^]*" || target.length === last || target[last] === "/";
}
__name(covers, "covers");
var RegExpRouter = class {
  static {
    __name(this, "RegExpRouter");
  }
  name = "RegExpRouter";
  #handlers;
  #tries;
  constructor() {
    this.#handlers = { ["ALL"]: [] };
    this.#tries = { ["ALL"]: new Trie() };
  }
  #insertPath(method, path) {
    try {
      this.#tries[method].insert(path, !/\*|\/:/.test(path));
    } catch (e) {
      throw e === PATH_ERROR ? new UnsupportedPathError(path) : e;
    }
  }
  add(method, path, handler) {
    const handlers = this.#handlers;
    if (!handlers) throw new Error(MESSAGE_MATCHER_IS_ALREADY_BUILT);
    const tries = this.#tries;
    if (!handlers[method]) {
      tries[method] = new Trie();
      handlers[method] = [...handlers["ALL"]];
      for (const p in tries["ALL"].paths) this.#insertPath(method, p);
    }
    if (path === "/*") path = "*";
    const methods = method === "ALL" ? Object.keys(handlers) : [method];
    const paths = checkOptionalParameter(path) || [path];
    for (const path2 of paths) for (const m of methods) {
      if (!tries[m].paths[path2]) this.#insertPath(m, path2);
      handlers[m].push([handler, path2]);
    }
  }
  match = match;
  buildAllMatchers() {
    const matchers = createNullObject();
    for (const method of Object.keys(this.#handlers)) matchers[method] = this.#buildMatcher(method);
    this.#handlers = this.#tries = void 0;
    return matchers;
  }
  #buildMatcher(method) {
    const handlers = this.#handlers[method];
    const trie = this.#tries[method];
    const staticMap = createNullObject();
    const handlerData = [];
    const [regexp, indexReplacementMap, paramReplacementMap] = trie.buildRegExp();
    const own = createNullObject();
    const entries = handlers.map(([h, p], i) => {
      (own[p] ??= []).push(i);
      return [h, trie.paths[p][1].reduceRight((map, [key, varIndex]) => {
        map[key] = paramReplacementMap[varIndex];
        return map;
      }, createNullObject())];
    });
    const wildcards = Object.keys(own).filter((p) => endsWithWildcard(trie.paths[p][2]));
    for (const path in trie.paths) {
      const [index, , keys] = trie.paths[path];
      const indexes = [...own[path]];
      for (const p of wildcards) if (p !== path && covers(trie.paths[p][2], keys)) indexes.push(...own[p]);
      const data = indexes.sort((a, b) => a - b).map((i) => entries[i]);
      if (index === -1) {
        const last = Math.max(-1, ...data.flatMap(([, map]) => Object.values(map)));
        staticMap[path] = [data, last === -1 ? emptyParam : path.match(regexp).slice(0, last + 1)];
      } else handlerData[index] = data;
    }
    return [
      regexp,
      indexReplacementMap.map((i) => handlerData[i]),
      staticMap
    ];
  }
};

// ../../../workspace/worker/node_modules/hono/dist/router/smart-router/router.js
var SmartRouter = class {
  static {
    __name(this, "SmartRouter");
  }
  name = "SmartRouter";
  #routers = [];
  #routes = [];
  constructor(init) {
    this.#routers = init.routers;
  }
  add(method, path, handler) {
    if (!this.#routes) throw new Error(MESSAGE_MATCHER_IS_ALREADY_BUILT);
    this.#routes.push([
      method,
      path,
      handler
    ]);
  }
  match(method, path) {
    if (!this.#routes) throw new Error("Fatal error");
    const routers = this.#routers;
    const routes = this.#routes;
    const len = routers.length;
    let i = 0;
    let res;
    for (; i < len; i++) {
      const router = routers[i];
      try {
        for (let i2 = 0, len2 = routes.length; i2 < len2; i2++) router.add(...routes[i2]);
        res = router.match(method, path);
      } catch (e) {
        if (e instanceof UnsupportedPathError) continue;
        throw e;
      }
      this.match = router.match.bind(router);
      this.#routers = [router];
      this.#routes = void 0;
      break;
    }
    if (i === len) throw new Error("Fatal error");
    this.name = `SmartRouter + ${this.activeRouter.name}`;
    return res;
  }
  get activeRouter() {
    if (this.#routes || this.#routers.length !== 1) throw new Error("No active router has been determined yet.");
    return this.#routers[0];
  }
};

// ../../../workspace/worker/node_modules/hono/dist/router/trie-router/node.js
var emptyParams = createNullObject();
var order = 0;
var Node3 = class Node4 {
  static {
    __name(this, "Node");
  }
  #methods = [];
  #children = createNullObject();
  #patterns = [];
  #pattern;
  #params = emptyParams;
  insert(method, path, handler) {
    let curNode = this;
    const parts = splitRoutingPath(path);
    const possibleKeys = /* @__PURE__ */ new Set();
    let i = 0;
    for (const p of parts) {
      const nextP = parts[++i];
      const pattern = getPattern(p, nextP) || (nextP === void 0 && p && p.indexOf("*") === p.length - 1 ? p : null);
      const isParam = Array.isArray(pattern);
      const key = isParam ? pattern[0] : pattern || p;
      const child = curNode.#children[key] ||= new Node4();
      if (pattern && !child.#pattern) {
        child.#pattern = pattern;
        curNode.#patterns.push(child);
      }
      curNode = child;
      if (isParam) possibleKeys.add(pattern[1]);
    }
    const methodMap = createNullObject();
    methodMap[method] = {
      handler,
      possibleKeys: [...possibleKeys],
      score: ++order
    };
    curNode.#methods.push(methodMap);
  }
  #pushHandlerSets(handlerSets, node, method, nodeParams, params) {
    for (let i = 0, len = node.#methods.length; i < len; i++) {
      const m = node.#methods[i];
      const handlerSet = m[method] || m["ALL"];
      if (handlerSet) {
        handlerSet.params = createNullObject();
        handlerSets.push(handlerSet);
        for (let i2 = 0, len2 = handlerSet.possibleKeys.length; i2 < len2; i2++) {
          const key = handlerSet.possibleKeys[i2];
          handlerSet.params[key] = params?.[key] && !i2 ? params[key] : nodeParams[key] ?? params?.[key];
        }
      }
    }
  }
  search(method, path) {
    const handlerSets = [];
    this.#params = emptyParams;
    let curNodes = [this];
    const parts = splitPath(path);
    const curNodesQueue = [];
    const len = parts.length;
    let partOffsets = null;
    for (let i = 0; i < len; i++) {
      const part = parts[i];
      const isLast = i === len - 1;
      const tempNodes = [];
      for (let j = 0, len2 = curNodes.length; j < len2; j++) {
        const node = curNodes[j];
        const nextNode = node.#children[part];
        if (nextNode) {
          nextNode.#params = node.#params;
          if (isLast) {
            if (nextNode.#children["*"]) this.#pushHandlerSets(handlerSets, nextNode.#children["*"], method, node.#params);
            this.#pushHandlerSets(handlerSets, nextNode, method, node.#params);
          } else tempNodes.push(nextNode);
        }
        for (const child of node.#patterns) {
          const pattern = child.#pattern;
          const params = node.#params === emptyParams ? {} : { ...node.#params };
          if (typeof pattern === "string") {
            if (pattern === "*" || part.startsWith(pattern.slice(0, -1))) {
              this.#pushHandlerSets(handlerSets, child, method, node.#params);
              if (pattern === "*") {
                child.#params = params;
                tempNodes.push(child);
              }
            }
            continue;
          }
          const [, name, matcher] = pattern;
          if (!part && matcher === true) continue;
          if (matcher !== true) {
            if (!partOffsets) {
              partOffsets = [];
              let offset = path[0] === "/" ? 1 : 0;
              for (let p = 0; p < len; p++) {
                partOffsets[p] = offset;
                offset += parts[p].length + 1;
              }
            }
            const restPathString = path.slice(partOffsets[i]);
            const m = matcher.exec(restPathString);
            if (m) {
              if (!Object.hasOwn(params, name)) params[name] = m[0];
              this.#pushHandlerSets(handlerSets, child, method, node.#params, params);
              if (m[0].length === restPathString.length && child.#children["*"]) this.#pushHandlerSets(handlerSets, child.#children["*"], method, node.#params, params);
              for (const _ in child.#children) {
                child.#params = params;
                const componentCount = m[0].match(/\//g)?.length ?? 0;
                (curNodesQueue[componentCount] ||= []).push(child);
                break;
              }
              continue;
            }
          }
          if (matcher === true || matcher.test(part)) {
            if (!Object.hasOwn(params, name)) params[name] = part;
            if (isLast) {
              this.#pushHandlerSets(handlerSets, child, method, params, node.#params);
              if (child.#children["*"]) this.#pushHandlerSets(handlerSets, child.#children["*"], method, params, node.#params);
            } else {
              child.#params = params;
              tempNodes.push(child);
            }
          }
        }
      }
      const shifted = curNodesQueue.shift();
      curNodes = shifted ? tempNodes.concat(shifted) : tempNodes;
    }
    if (handlerSets[1]) handlerSets.sort((a, b) => {
      return a.score - b.score;
    });
    return [handlerSets.map(({ handler, params }) => [handler, params])];
  }
};

// ../../../workspace/worker/node_modules/hono/dist/router/trie-router/router.js
var TrieRouter = class {
  static {
    __name(this, "TrieRouter");
  }
  name = "TrieRouter";
  #node = new Node3();
  add(method, path, handler) {
    for (const result of checkOptionalParameter(path) || [path]) this.#node.insert(method, result, handler);
  }
  match(method, path) {
    return this.#node.search(method, path);
  }
};

// ../../../workspace/worker/node_modules/hono/dist/hono.js
var Hono3 = class extends Hono {
  static {
    __name(this, "Hono");
  }
  /**
  * Creates an instance of the Hono class.
  *
  * @param options - Optional configuration options for the Hono instance.
  */
  constructor(options = {}) {
    super(options);
    this.router = options.router ?? new SmartRouter({ routers: [new RegExpRouter(), new TrieRouter()] });
  }
};

// src/admin-page.ts
var ADMIN_HTML = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>bylwapp \u6570\u636E\u91C7\u96C6\u7BA1\u7406\u7CFB\u7EDF</title>
  <link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='8' fill='%230E7C73'/%3E%3C/svg%3E">
  <style>
    :root {
      --brand: #0e7c73;
      --brand-dark: #0b5f59;
      --brand-soft: #e7f5f3;
      --ink: #12211e;
      --muted: #5d6d69;
      --line: #e4eeeb;
      --bg: #f3f7f6;
      --card: #ffffff;
      --sidebar: #0c1c1a;
      --side-text: #d7e6e2;
      --ok: #067647;
      --ok-bg: #e7f6ee;
      --wait: #b54708;
      --wait-bg: #fef4e6;
      --bad: #b42318;
      --bad-bg: #fdeceb;
      --shadow: 0 1px 2px rgba(16, 33, 30, 0.05), 0 10px 28px rgba(16, 33, 30, 0.05);
      --radius: 16px;
      --font: "PingFang SC", "Hiragino Sans GB", "Noto Sans SC", "Microsoft YaHei", "Segoe UI", sans-serif;
      --mono: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    }
    * { box-sizing: border-box; }
    [hidden] { display: none !important; }
    html, body { margin: 0; min-height: 100%; }
    body { font: 14px/1.5 var(--font); color: var(--ink); background: var(--bg); }
    button, input, select { font: inherit; color: inherit; }
    button { cursor: pointer; }
    h1, h2, p { margin: 0; }
    .mark { width: 36px; height: 36px; display: block; }
    .login-screen { min-height: 100vh; display: grid; place-items: center; padding: 24px; background: radial-gradient(900px 480px at 50% -10%, #d7f3ef 0%, var(--bg) 55%); }
    .login-card { width: min(420px, 100%); background: var(--card); border: 1px solid var(--line); border-radius: 24px; box-shadow: var(--shadow); padding: 32px 28px 28px; }
    .login-brand { display: flex; gap: 12px; align-items: center; margin-bottom: 22px; }
    .login-brand strong { display: block; font-size: 18px; letter-spacing: -0.02em; }
    .login-brand span { color: var(--muted); font-size: 13px; }
    .field { display: flex; flex-direction: column; gap: 6px; margin-bottom: 14px; font-size: 13px; color: var(--muted); }
    .field input, .field select, .toolbar select, .toolbar input { border: 1px solid var(--line); background: #fff; border-radius: 12px; padding: 10px 12px; outline: none; }
    .field input:focus, .field select:focus, .toolbar select:focus { border-color: var(--brand); box-shadow: 0 0 0 3px rgba(14, 124, 115, 0.15); }
    .primary, .ghost, .seg button { border-radius: 12px; border: 1px solid transparent; padding: 10px 14px; }
    .primary { background: var(--brand); color: white; width: 100%; font-weight: 600; }
    .primary:hover { background: var(--brand-dark); }
    .ghost { background: white; border-color: var(--line); color: var(--ink); }
    .login-error { display: none; margin-top: 12px; padding: 10px 12px; border-radius: 12px; background: var(--bad-bg); color: var(--bad); }
    .login-foot { margin-top: 16px; color: var(--muted); font-size: 12px; }
    .shell { min-height: 100vh; display: flex; }
    .sidebar { width: 240px; flex: none; background: var(--sidebar); color: var(--side-text); display: flex; flex-direction: column; padding: 18px 12px; position: sticky; top: 0; height: 100vh; }
    .side-brand { display: flex; gap: 10px; align-items: center; padding: 4px 8px 18px; color: white; }
    .side-brand strong { display: block; font-size: 15px; }
    .side-brand span { display: block; font-size: 12px; color: #9fb8b3; }
    .nav { display: flex; flex-direction: column; gap: 4px; }
    .nav button { display: flex; align-items: center; gap: 10px; width: 100%; text-align: left; background: transparent; color: var(--side-text); border: 0; border-radius: 10px; padding: 9px 10px; }
    .nav button svg { width: 18px; height: 18px; flex: none; }
    .nav button.active { background: rgba(255,255,255,0.1); color: white; font-weight: 650; }
    .nav .split { height: 1px; background: rgba(255,255,255,0.08); margin: 8px 8px; }
    .side-note { margin-top: auto; padding: 12px 10px 4px; font-size: 12px; color: #8eaaa4; }
    .workspace { flex: 1; min-width: 0; display: flex; flex-direction: column; }
    .topbar { height: 64px; display: flex; align-items: center; gap: 12px; padding: 0 22px; background: rgba(255,255,255,0.92); border-bottom: 1px solid var(--line); position: sticky; top: 0; z-index: 5; backdrop-filter: blur(10px); }
    .topbar h1 { font-size: 18px; letter-spacing: -0.02em; flex: 1; }
    .top-actions { display: flex; align-items: center; gap: 10px; }
    .updated { color: var(--muted); font-size: 12px; white-space: nowrap; }
    .icon-btn { display: none; width: 38px; height: 38px; border-radius: 10px; border: 1px solid var(--line); background: white; align-items: center; justify-content: center; }
    .user-wrap { position: relative; }
    .user-btn { display: flex; flex-direction: column; align-items: flex-end; background: white; border: 1px solid var(--line); border-radius: 12px; padding: 6px 10px; min-width: 96px; }
    .user-btn strong { font-size: 13px; }
    .user-btn span { font-size: 11px; color: var(--muted); }
    .user-menu { position: absolute; right: 0; top: calc(100% + 6px); background: white; border: 1px solid var(--line); border-radius: 12px; box-shadow: var(--shadow); padding: 6px; min-width: 140px; }
    .user-menu button { width: 100%; background: transparent; border: 0; text-align: left; border-radius: 8px; padding: 8px 10px; }
    .user-menu button:hover { background: var(--bg); }
    .content { padding: 22px; display: flex; flex-direction: column; gap: 16px; }
    .banner { display: none; margin: 16px 22px 0; padding: 10px 12px; border-radius: 12px; background: var(--bad-bg); color: var(--bad); }
    .kpi { display: grid; grid-template-columns: repeat(6, minmax(0, 1fr)); gap: 12px; }
    .card, .panel { background: var(--card); border: 1px solid var(--line); border-radius: var(--radius); box-shadow: var(--shadow); }
    .kpi .card { padding: 14px 14px 12px; }
    .kpi .label { color: var(--muted); font-size: 12px; }
    .kpi .value { margin-top: 6px; font-size: 26px; font-weight: 680; letter-spacing: -0.03em; font-variant-numeric: tabular-nums; }
    .kpi .hint { margin-top: 4px; color: var(--muted); font-size: 12px; }
    .panel { padding: 16px; }
    .panel-head { display: flex; justify-content: space-between; gap: 12px; align-items: center; margin-bottom: 12px; flex-wrap: wrap; }
    .panel-head h2 { font-size: 16px; }
    .sub { color: var(--muted); font-size: 12px; margin-top: 2px; }
    .seg { display: flex; background: var(--bg); border-radius: 12px; padding: 3px; gap: 2px; }
    .seg button { background: transparent; border: 0; color: var(--muted); padding: 6px 10px; border-radius: 9px; }
    .seg button.on { background: white; color: var(--ink); box-shadow: 0 1px 2px rgba(16,33,30,.08); }
    .chart-wrap { height: 240px; }
    svg.chart { width: 100%; height: 240px; display: block; }
    .device-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: 12px; }
    .device-card { padding: 14px; }
    .device-card header { display: flex; justify-content: space-between; gap: 8px; align-items: flex-start; }
    .device-card h3 { font-size: 15px; font-weight: 650; }
    .badge { display: inline-flex; align-items: center; gap: 6px; border-radius: 999px; padding: 2px 8px; font-size: 12px; font-weight: 650; white-space: nowrap; }
    .badge.ok { background: var(--ok-bg); color: var(--ok); }
    .badge.wait { background: var(--wait-bg); color: var(--wait); }
    .badge.bad { background: var(--bad-bg); color: var(--bad); }
    .badge.neutral { background: #eef2f1; color: #52615d; }
    .meta { margin-top: 8px; color: var(--muted); font-size: 13px; }
    table { width: 100%; border-collapse: collapse; }
    th, td { text-align: left; padding: 10px 8px; border-bottom: 1px solid var(--line); vertical-align: middle; font-size: 13px; }
    th { color: var(--muted); font-weight: 600; font-size: 12px; }
    #records tbody tr { cursor: pointer; }
    #records tbody tr:hover { background: #f7fbfa; }
    .toolbar { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
    .pager { display: flex; justify-content: space-between; align-items: center; gap: 8px; margin-top: 12px; color: var(--muted); font-size: 13px; }
    .rq-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
    .rq-stats { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 8px; margin: 12px 0; }
    .stat { background: var(--bg); border-radius: 12px; padding: 10px; }
    .stat b { display: block; font-size: 18px; font-variant-numeric: tabular-nums; }
    .stat span { color: var(--muted); font-size: 12px; }
    .export-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 12px; }
    .export-grid button { text-align: left; background: white; }
    .export-grid button small { display: block; color: var(--muted); font-weight: 400; }
    .forms { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
    .pair-code { font: 700 36px/1 var(--mono); letter-spacing: 0.28em; margin: 8px 0 0; color: var(--brand-dark); }
    .empty { border: 1px dashed #c9d8d4; border-radius: 14px; padding: 28px 16px; text-align: center; color: var(--muted); }
    .empty strong { display: block; color: var(--ink); margin-bottom: 4px; }
    .sk { position: relative; overflow: hidden; color: transparent !important; background: #e7eeec; border-radius: 8px; }
    .sk::after { content: ""; position: absolute; inset: 0; background: linear-gradient(90deg, transparent, rgba(255,255,255,.7), transparent); animation: shine 1.2s infinite; }
    @keyframes shine { from { transform: translateX(-100%); } to { transform: translateX(100%); } }
    .backdrop { display: none; }
    .drawer { position: fixed; inset: 0; background: rgba(12, 28, 26, 0.38); z-index: 40; display: flex; justify-content: flex-end; }
    .drawer[hidden] { display: none; }
    .drawer-panel { width: min(480px, 100%); height: 100%; background: white; padding: 18px; overflow: auto; box-shadow: var(--shadow); }
    .drawer-panel header { display: flex; justify-content: space-between; gap: 12px; align-items: flex-start; margin-bottom: 12px; }
    pre { margin: 0; white-space: pre-wrap; word-break: break-word; font: 12px/1.55 var(--mono); background: #0c1c1a; color: #e7f5f3; border-radius: 12px; padding: 12px; }
    .hash { font-family: var(--mono); font-size: 12px; color: var(--muted); }
    @media (max-width: 1100px) {
      .kpi { grid-template-columns: repeat(3, minmax(0, 1fr)); }
      .rq-grid, .forms { grid-template-columns: 1fr; }
    }
    @media (max-width: 860px) {
      .icon-btn { display: inline-flex; }
      .sidebar { position: fixed; z-index: 30; transform: translateX(-105%); transition: transform .18s ease; }
      .sidebar.open { transform: none; }
      .backdrop.show { display: block; position: fixed; inset: 0; background: rgba(12,28,26,.35); z-index: 25; }
      .kpi { grid-template-columns: 1fr 1fr; }
      .content, .topbar { padding-left: 14px; padding-right: 14px; }
      .updated { display: none; }
      .user-btn { min-width: 0; }
    }
  </style>
</head>
<body>
  <div id="login-screen" class="login-screen">
    <form id="login-form" class="login-card">
      <div class="login-brand">
        <svg class="mark" viewBox="0 0 32 32" aria-hidden="true"><rect width="32" height="32" rx="8" fill="#0E7C73"/><path d="M6 17h4l2.2-6 3.2 11 2.3-5H26" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
        <div>
          <strong>bylwapp \u6570\u636E\u91C7\u96C6\u7BA1\u7406\u7CFB\u7EDF</strong>
          <span>\u62A4\u7406\u8005 / \u7BA1\u7406\u5458\u767B\u5F55</span>
        </div>
      </div>
      <label class="field">\u7528\u6237\u540D<input name="username" required autocomplete="username"></label>
      <label class="field">\u5BC6\u7801<input name="password" type="password" required autocomplete="current-password"></label>
      <button class="primary" type="submit">\u767B\u5F55</button>
      <div id="login-error" class="login-error"></div>
      <p class="login-foot">\u8FD9\u91CC\u53EA\u5C55\u793A\u670D\u52A1\u5668\u5DF2\u7ECF\u6536\u5230\u7684\u526F\u672C\u3002\u6700\u8FD1 100 \u6761\u4E0D\u662F\u4E22\u5931\u6E05\u5355\uFF0C\u4E5F\u4E0D\u80FD\u5F53\u4F5C\u8BBA\u6587\u7ED3\u679C\u3002</p>
    </form>
  </div>
  <div id="app" class="shell" hidden>
    <aside id="sidebar" class="sidebar">
      <div class="side-brand">
        <svg class="mark" viewBox="0 0 32 32" aria-hidden="true"><rect width="32" height="32" rx="8" fill="#0E7C73"/><path d="M6 17h4l2.2-6 3.2 11 2.3-5H26" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
        <div><strong>bylwapp</strong><span>\u6570\u636E\u91C7\u96C6\u7BA1\u7406\u7CFB\u7EDF</span></div>
      </div>
      <nav class="nav" id="nav">
        <button type="button" data-view="overview" class="active"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M4 13h6V4H4v9zm10 7h6V4h-6v16zM4 20h6v-5H4v5z"/></svg>\u6982\u89C8</button>
        <button type="button" data-view="devices"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="7" y="2" width="10" height="20" rx="2"/><path d="M11 18h2"/></svg>\u91C7\u96C6\u8BBE\u5907</button>
        <button type="button" data-view="records"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01"/></svg>\u6570\u636E\u8BB0\u5F55</button>
        <button type="button" data-view="research"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M4 19V5M4 19h16"/><path d="M8 15l4-5 3 3 5-7"/></svg>\u7814\u7A76\u6307\u6807</button>
        <button type="button" data-view="reconcile"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M12 8v5M12 17h.01"/><path d="M10.3 4.5 2.8 18a2 2 0 0 0 1.7 3h15a2 2 0 0 0 1.7-3L13.7 4.5a2 2 0 0 0-3.4 0z"/></svg>\u5BF9\u8D26\u4E0E\u51B2\u7A81</button>
        <button type="button" data-view="exports"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M12 4v10m0 0 4-4m-4 4-4-4"/><path d="M5 19h14"/></svg>\u6570\u636E\u5BFC\u51FA</button>
        <div class="split"></div>
        <button type="button" data-view="settings"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9c.3.6.9 1 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/></svg>\u8BBE\u7F6E</button>
      </nav>
      <p class="side-note">\u6700\u8FD1 100 \u6761\u662F\u53EF\u89C1\u6027\u89C6\u56FE\uFF0C\u4E0D\u662F\u4E22\u5931\u6E05\u5355\uFF0C\u4E5F\u4E0D\u80FD\u5F53\u4F5C\u8BBA\u6587\u7ED3\u679C\u3002</p>
    </aside>
    <div id="backdrop" class="backdrop"></div>
    <div class="workspace">
      <header class="topbar">
        <button id="menu" class="icon-btn" type="button" aria-label="\u6253\u5F00\u5BFC\u822A"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M4 7h16M4 12h16M4 17h16"/></svg></button>
        <h1 id="view-title">\u6982\u89C8</h1>
        <div class="top-actions">
          <span id="updated" class="updated">\u5C1A\u672A\u5237\u65B0</span>
          <button id="refresh" class="ghost" type="button">\u5237\u65B0</button>
          <div class="user-wrap">
            <button id="user-btn" class="user-btn" type="button"><strong id="user-name">\u2014</strong><span id="user-role">\u2014</span></button>
            <div id="user-menu" class="user-menu" hidden><button id="logout" type="button">\u9000\u51FA\u767B\u5F55</button></div>
          </div>
        </div>
      </header>
      <div id="banner" class="banner"></div>
      <main class="content">
        <section id="view-overview">
          <div id="kpi" class="kpi"></div>
          <section class="panel">
            <div class="panel-head">
              <div>
                <h2>\u8D8B\u52BF</h2>
                <p class="sub" id="chart-sub">\u6309\u670D\u52A1\u5668\u6536\u5230\u7684\u65F6\u95F4</p>
              </div>
              <div class="toolbar">
                <select id="series-type" aria-label="\u6307\u6807">
                  <option value="heart_rate">\u5FC3\u7387</option>
                  <option value="blood_pressure">\u8840\u538B\u6536\u7F29\u538B</option>
                  <option value="spo2">\u8840\u6C27</option>
                  <option value="temperature">\u4F53\u6E29</option>
                  <option value="steps">\u6B65\u6570</option>
                  <option value="stress">\u538B\u529B</option>
                  <option value="hrv">\u5FC3\u7387\u53D8\u5F02</option>
                </select>
                <div class="seg" id="range">
                  <button type="button" data-range="24h">24 \u5C0F\u65F6</button>
                  <button type="button" data-range="7d" class="on">7 \u5929</button>
                  <button type="button" data-range="30d">30 \u5929</button>
                  <button type="button" data-range="all">\u5168\u90E8</button>
                </div>
              </div>
            </div>
            <div class="chart-wrap"><svg id="chart" class="chart" viewBox="0 0 720 240" role="img" aria-label="\u8D8B\u52BF\u56FE"></svg></div>
          </section>
          <section class="panel">
            <div class="panel-head"><div><h2>\u91C7\u96C6\u7AEF\u72B6\u6001</h2><p class="sub">\u8D85\u8FC7 15 \u5206\u949F\u6CA1\u6709\u65B0\u56DE\u6267\u4F1A\u6807\u6210\u540C\u6B65\u504F\u65E7</p></div><button class="ghost" type="button" data-jump="devices">\u5168\u90E8\u8BBE\u5907</button></div>
            <div id="overview-devices" class="device-grid"></div>
          </section>
        </section>
        <section id="view-devices" hidden>
          <section class="panel">
            <div class="panel-head"><div><h2>\u91C7\u96C6\u8BBE\u5907</h2><p class="sub">\u624B\u673A\u5E94\u7528\u4F1A\u81EA\u52A8\u767B\u8BB0\u3002\u7BA1\u7406\u5458\u4E5F\u53EF\u4EE5\u5728\u8BBE\u7F6E\u91CC\u6DFB\u52A0\u3002</p></div></div>
            <div id="device-table"></div>
          </section>
        </section>
        <section id="view-records" hidden>
          <section class="panel">
            <div class="panel-head">
              <div><h2>\u6570\u636E\u8BB0\u5F55</h2><p class="sub" id="records-note">\u6700\u8FD1 100 \u6761\u56DE\u6267</p></div>
              <div class="toolbar">
                <select id="filter-type" aria-label="\u7C7B\u578B"><option value="">\u5168\u90E8\u7C7B\u578B</option></select>
                <select id="filter-device" aria-label="\u8BBE\u5907"><option value="">\u5168\u90E8\u8BBE\u5907</option></select>
                <select id="filter-range" aria-label="\u65F6\u95F4"><option value="all">\u5168\u90E8\u65F6\u95F4</option><option value="24h">24 \u5C0F\u65F6</option><option value="7d">7 \u5929</option><option value="30d">30 \u5929</option></select>
              </div>
            </div>
            <div id="records"></div>
            <div class="pager"><span id="page-label"></span><span><button class="ghost" id="prev" type="button">\u4E0A\u4E00\u9875</button> <button class="ghost" id="next" type="button">\u4E0B\u4E00\u9875</button></span></div>
          </section>
        </section>
        <section id="view-research" hidden>
          <div id="rq" class="rq-grid"></div>
        </section>
        <section id="view-reconcile" hidden>
          <div id="recon-kpi" class="kpi"></div>
          <section class="panel">
            <div class="panel-head"><div><h2>\u51B2\u7A81</h2><p class="sub">\u76F8\u540C event_id\u3001\u4E0D\u540C payload_hash \u65F6\u4FDD\u7559\u7B2C\u4E00\u4EFD\u56DE\u6267\u3002</p></div></div>
            <div id="conflicts"></div>
          </section>
        </section>
        <section id="view-exports" hidden>
          <div class="export-grid" id="exports"></div>
        </section>
        <section id="view-settings" hidden>
          <div class="forms">
            <section class="panel" id="admin-forms">
              <h2>\u767B\u8BB0\u91C7\u96C6\u7AEF</h2>
              <p class="sub">\u53D1\u7ED9\u8FD8\u6CA1\u6709\u81EA\u52A8\u767B\u8BB0\u7684\u624B\u673A\u3002</p>
              <form id="device-form" style="margin-top:12px">
                <label class="field">\u91C7\u96C6\u7AEF ID<input name="device_id" required autocomplete="off"></label>
                <label class="field">\u540D\u79F0<input name="name" required autocomplete="off"></label>
                <button class="primary" type="submit" style="width:auto">\u767B\u8BB0</button>
              </form>
            </section>
            <section class="panel">
              <h2>6 \u4F4D\u914D\u5BF9\u7801</h2>
              <p class="sub">10 \u5206\u949F\u5185\u6709\u6548\uFF0C\u624B\u673A\u7528\u4E00\u6B21\u540E\u5931\u6548\u3002</p>
              <form id="pair-form" style="margin-top:12px">
                <label class="field">\u91C7\u96C6\u7AEF ID<input name="device_id" required autocomplete="off"></label>
                <button class="primary" type="submit" style="width:auto">\u751F\u6210\u914D\u5BF9\u7801</button>
              </form>
              <p id="pair-code" class="pair-code"></p>
              <p id="pair-note" class="sub"></p>
            </section>
          </div>
          <p id="settings-lock" class="empty" hidden><strong>\u9700\u8981\u7BA1\u7406\u5458</strong>\u62A4\u7406\u8005\u53EF\u4EE5\u67E5\u770B\u6570\u636E\uFF0C\u767B\u8BB0\u8BBE\u5907\u548C\u914D\u5BF9\u7801\u53EA\u5BF9\u7BA1\u7406\u5458\u5F00\u653E\u3002</p>
        </section>
      </main>
    </div>
  </div>
  <div id="drawer" class="drawer" hidden>
    <div class="drawer-panel">
      <header>
        <div><h2 id="drawer-title">\u8BB0\u5F55</h2><p id="drawer-sub" class="sub"></p></div>
        <button id="drawer-close" class="ghost" type="button">\u5173\u95ED</button>
      </header>
      <p id="drawer-hash" class="hash"></p>
      <pre id="drawer-json"></pre>
    </div>
  </div>
  <script>
    var TITLES = { overview: "\u6982\u89C8", devices: "\u91C7\u96C6\u8BBE\u5907", records: "\u6570\u636E\u8BB0\u5F55", research: "\u7814\u7A76\u6307\u6807 RQ1\u2013RQ4", reconcile: "\u5BF9\u8D26\u4E0E\u51B2\u7A81", exports: "\u6570\u636E\u5BFC\u51FA", settings: "\u8BBE\u7F6E" };
    var TYPES = { blood_pressure: "\u8840\u538B", heart_rate: "\u5FC3\u7387", steps: "\u6B65\u6570", spo2: "\u8840\u6C27", sleep: "\u7761\u7720", sleep_session: "\u7761\u7720\u65F6\u6BB5", stress: "\u538B\u529B", hrv: "\u5FC3\u7387\u53D8\u5F02", temperature: "\u4F53\u6E29", operating_state: "\u8FD0\u884C\u72B6\u6001", reminder: "\u63D0\u9192", care_attention: "\u7167\u62A4\u5173\u6CE8", worn_state: "\u4F69\u6234", data_gap: "\u6570\u636E\u7F3A\u53E3", usability_task: "\u53EF\u7528\u6027\u4EFB\u52A1", sus: "SUS \u95EE\u5377" };
    var KINDS = { blood_pressure: "\u8840\u538B\u8BA1", heart_rate: "\u5FC3\u7387\u5E26", ring: "\u6212\u6307", collector: "\u91C7\u96C6\u7AEF" };
    var OPS = { NOMINAL: "\u6B63\u5E38", BLE_DISCONNECTED: "\u84DD\u7259\u65AD\u5F00", NETWORK_DEGRADED: "\u7F51\u7EDC\u964D\u7EA7", AUTH_FAILURE: "\u8BA4\u8BC1\u5931\u8D25", CLOCK_DEGRADED: "\u65F6\u949F\u5F02\u5E38" };
    var PREFER = ["heart_rate", "blood_pressure", "spo2", "temperature", "steps", "stress", "hrv"];
    var state = { token: "", role: "", username: "", view: "overview", devices: [], events: [], conflicts: [], series: [], seriesType: "heart_rate", seriesTouched: false, range: "7d", page: 1, pageSize: 8, loading: false, updatedAt: null, rq: null, recon: null, note: "" };
    function $(id) { return document.getElementById(id); }
    function token() { return sessionStorage.getItem("bylw_token") || ""; }
    function clearError() { $("banner").style.display = "none"; }
    function showError(error) { var el = $("banner"); el.style.display = "block"; el.textContent = error && error.message ? error.message : String(error); }
    function api(path, options) {
      var headers = { Authorization: "Bearer " + state.token };
      if (options && options.headers) Object.keys(options.headers).forEach(function (key) { headers[key] = options.headers[key]; });
      return fetch(path, { method: (options && options.method) || "GET", headers: headers, body: options && options.body }).then(function (response) {
        return response.text().then(function (text) {
          var data = text ? JSON.parse(text) : null;
          if (response.status === 401) { logout(); throw new Error("\u8BF7\u91CD\u65B0\u767B\u5F55"); }
          if (!response.ok) throw new Error((data && data.error) || response.statusText);
          return data;
        });
      });
    }
    function shanghai(date) {
      return new Intl.DateTimeFormat("zh-CN", { timeZone: "Asia/Shanghai", month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(date);
    }
    function dayKey(date) {
      return new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Shanghai", year: "numeric", month: "2-digit", day: "2-digit" }).format(date);
    }
    function relative(iso) {
      if (!iso) return "\u5C1A\u65E0\u4E0A\u62A5";
      var date = new Date(iso);
      if (isNaN(date.getTime())) return "\u65F6\u95F4\u672A\u77E5";
      var diff = Date.now() - date.getTime();
      var abs = shanghai(date);
      if (diff < 0) return abs;
      if (diff < 60000) return "\u521A\u521A";
      if (diff < 3600000) return Math.floor(diff / 60000) + " \u5206\u949F\u524D";
      if (diff < 86400000) return Math.floor(diff / 3600000) + " \u5C0F\u65F6\u524D";
      if (diff < 7 * 86400000) return Math.floor(diff / 86400000) + " \u5929\u524D";
      return abs;
    }
    function within(iso, range) {
      if (!range || range === "all" || !iso) return range === "all" || !range;
      var diff = Date.now() - new Date(iso).getTime();
      if (range === "24h") return diff <= 86400000;
      if (range === "7d") return diff <= 7 * 86400000;
      if (range === "30d") return diff <= 30 * 86400000;
      return true;
    }
    function num(value) {
      if (typeof value !== "number" || !isFinite(value)) return value == null ? "" : String(value);
      if (Math.abs(value - Math.round(value)) < 1e-6) return String(Math.round(value));
      return String(Math.round(value * 10) / 10);
    }
    function humanValue(event) {
      var v = event.values || {};
      var t = event.measurement_type;
      if (t === "heart_rate" && v.bpm != null) return "\u5FC3\u7387 " + num(v.bpm) + " bpm";
      if (t === "blood_pressure" && v.systolic != null) return "\u8840\u538B " + num(v.systolic) + "/" + num(v.diastolic) + " mmHg" + (v.pulse != null ? " \xB7 \u8109\u640F " + num(v.pulse) : "");
      if (t === "spo2" && v.spo2 != null) return "\u8840\u6C27 " + num(v.spo2) + "%";
      if (t === "temperature" && v.celsius != null) return "\u4F53\u6E29 " + num(v.celsius) + " \xB0C";
      if (t === "steps" && v.steps != null) return "\u6B65\u6570 " + num(v.steps);
      if (t === "stress" && v.stress != null) return "\u538B\u529B " + num(v.stress);
      if (t === "hrv" && v.hrv_ms != null) return "HRV " + num(v.hrv_ms) + " ms";
      if (t === "sleep" || t === "sleep_session") return (TYPES[t] || "\u7761\u7720") + (v.stage ? " " + v.stage : "") + (v.duration_min != null ? " " + num(v.duration_min) + " \u5206\u949F" : "");
      if (t === "worn_state") return v.worn ? "\u4F69\u6234\u4E2D" : "\u672A\u4F69\u6234";
      if (t === "reminder") return "\u63D0\u9192 " + (v.disposition || "");
      if (t === "operating_state") return "\u8FD0\u884C " + (OPS[v.state] || v.state || OPS[event.operating_state] || "");
      if (t === "sus") return "SUS \u95EE\u5377";
      return (TYPES[t] || t || "\u8BB0\u5F55") + (event.unit ? " \xB7 " + event.unit : "");
    }
    function deviceStatus(device) {
      if (!device.last_received_at) return { cls: "neutral", text: "\u672A\u4E0A\u62A5" };
      if (device.stale) return { cls: "wait", text: "\u540C\u6B65\u504F\u65E7" };
      return { cls: "ok", text: "\u5728\u7EBF" };
    }
    function el(tag, className, text) {
      var node = document.createElement(tag);
      if (className) node.className = className;
      if (text != null) node.textContent = text;
      return node;
    }
    function badge(info) { return el("span", "badge " + info.cls, info.text); }
    function empty(title, text) {
      var box = el("div", "empty");
      box.append(el("strong", "", title), document.createTextNode(text));
      return box;
    }
    function table(headers, rows) {
      var tableEl = document.createElement("table");
      var head = document.createElement("tr");
      headers.forEach(function (label) { head.append(el("th", "", label)); });
      tableEl.append(head);
      rows.forEach(function (row) {
        var tr = document.createElement("tr");
        row.cells.forEach(function (cell) { var td = document.createElement("td"); if (cell instanceof Node) td.append(cell); else td.textContent = cell == null ? "" : String(cell); tr.append(td); });
        if (row.onClick) tr.addEventListener("click", row.onClick);
        tableEl.append(tr);
      });
      return tableEl;
    }
    function chooseSeriesType(events) {
      var seen = {};
      events.forEach(function (item) { if (item.event) seen[item.event.measurement_type] = true; });
      for (var i = 0; i < PREFER.length; i++) if (seen[PREFER[i]]) return PREFER[i];
      return "heart_rate";
    }
    function setLoading(on) {
      state.loading = on;
      $("refresh").disabled = on;
      if (on && !state.devices.length && !state.events.length) {
        $("kpi").replaceChildren();
        for (var i = 0; i < 6; i++) {
          var card = el("article", "card");
          card.append(el("div", "label sk", "\u6307\u6807"), el("div", "value sk", "00"), el("div", "hint sk", "\u52A0\u8F7D"));
          $("kpi").append(card);
        }
      }
    }
    function paintUser() {
      $("user-name").textContent = state.username || "\u5DF2\u767B\u5F55";
      $("user-role").textContent = state.role === "admin" ? "\u7BA1\u7406\u5458" : state.role === "caregiver" ? "\u62A4\u7406\u8005" : "\u7528\u6237";
      var admin = state.role === "admin";
      $("admin-forms").hidden = !admin;
      $("pair-form").parentElement.hidden = !admin;
      $("settings-lock").hidden = admin;
    }
    function showView(name) {
      state.view = name;
      Object.keys(TITLES).forEach(function (key) {
        var section = $("view-" + key);
        if (section) section.hidden = key !== name;
      });
      $("view-title").textContent = TITLES[name];
      document.querySelectorAll("#nav button").forEach(function (button) { button.classList.toggle("active", button.getAttribute("data-view") === name); });
      $("sidebar").classList.remove("open");
      $("backdrop").classList.remove("show");
      if (name === "research") ensureRQ();
      if (name === "reconcile") ensureRecon();
    }
    function renderAll() {
      renderKpi();
      renderChart();
      renderOverviewDevices();
      renderDeviceTable();
      renderRecords();
      renderConflicts();
      if (state.updatedAt) $("updated").textContent = "\u66F4\u65B0\u4E8E " + shanghai(state.updatedAt);
    }
    function renderKpi() {
      var eventsTotal = state.devices.reduce(function (sum, device) { return sum + (device.event_count || 0); }, 0);
      var conflicts = state.devices.reduce(function (sum, device) { return sum + (device.open_conflicts || 0); }, 0);
      var duplicates = state.devices.reduce(function (sum, device) { return sum + (device.duplicate_acks || 0); }, 0);
      var today = dayKey(new Date());
      var todayCount = state.events.filter(function (item) { return item.server_received_at && dayKey(new Date(item.server_received_at)) === today; }).length;
      var latest = null;
      state.devices.forEach(function (device) {
        if (device.last_received_at && (!latest || device.last_received_at > latest)) latest = device.last_received_at;
      });
      var cards = [
        ["\u8BBE\u5907\u6570", String(state.devices.length), "\u5DF2\u767B\u8BB0\u91C7\u96C6\u7AEF"],
        ["\u4E8B\u4EF6\u603B\u6570", String(eventsTotal), "\u5168\u90E8\u5DF2\u5165\u5E93"],
        ["\u4ECA\u65E5\u4E8B\u4EF6", String(todayCount), "\u4E0A\u6D77\u65F6\u533A \xB7 \u6700\u8FD1 100 \u6761\u5185"],
        ["\u51B2\u7A81", String(conflicts), "\u4FDD\u7559\u9996\u6B21\u56DE\u6267"],
        ["\u91CD\u590D\u786E\u8BA4", String(duplicates), "\u76F8\u540C\u54C8\u5E0C\u518D\u6B21\u4E0A\u4F20"],
        ["\u6700\u8FD1\u4E0A\u62A5", latest ? relative(latest) : "\u5C1A\u65E0", latest ? shanghai(new Date(latest)) : "\u8FD8\u6CA1\u6709\u56DE\u6267"]
      ];
      $("kpi").replaceChildren();
      cards.forEach(function (item) {
        var card = el("article", "card");
        card.append(el("div", "label", item[0]), el("div", "value", item[1]), el("div", "hint", item[2]));
        $("kpi").append(card);
      });
    }
    function renderChart() {
      var svg = $("chart");
      svg.replaceChildren();
      var points = state.series.filter(function (point) { return within(point.at, state.range); }).slice().reverse();
      var label = ($("series-type").selectedOptions[0] && $("series-type").selectedOptions[0].textContent) || "\u6307\u6807";
      $("chart-sub").textContent = points.length ? label + " \xB7 " + points.length + " \u4E2A\u70B9 \xB7 \u670D\u52A1\u5668\u6536\u5230\u65F6\u95F4\uFF08\u4E0A\u6D77\uFF09" : label + "\u5728\u8FD9\u4E2A\u65F6\u95F4\u8303\u56F4\u5185\u8FD8\u6CA1\u6709\u70B9";
      if (points.length < 2) {
        var text = document.createElementNS("http://www.w3.org/2000/svg", "text");
        text.setAttribute("x", "24"); text.setAttribute("y", "120"); text.setAttribute("fill", "#5d6d69");
        text.textContent = points.length === 0 ? "\u8FD8\u6CA1\u6709\u8DB3\u591F\u7684\u6570\u636E\u3002" : "\u81F3\u5C11\u9700\u8981\u4E24\u4E2A\u70B9\u624D\u753B\u8D8B\u52BF\u3002";
        svg.append(text);
        return;
      }
      var values = points.map(function (point) { return Number(point.value) || 0; });
      var min = Math.min.apply(null, values);
      var max = Math.max.apply(null, values);
      var span = max - min || 1;
      var ns = "http://www.w3.org/2000/svg";
      for (var g = 0; g < 4; g++) {
        var gy = 28 + g * 48;
        var grid = document.createElementNS(ns, "line");
        grid.setAttribute("x1", "56"); grid.setAttribute("x2", "700"); grid.setAttribute("y1", String(gy)); grid.setAttribute("y2", String(gy));
        grid.setAttribute("stroke", "#e4eeeb");
        svg.append(grid);
      }
      var coords = points.map(function (point, index) {
        var x = 56 + (index * 644) / (points.length - 1);
        var y = 200 - ((Number(point.value) - min) / span) * 160;
        return x.toFixed(1) + "," + y.toFixed(1);
      }).join(" ");
      var line = document.createElementNS(ns, "polyline");
      line.setAttribute("fill", "none"); line.setAttribute("stroke", "#0E7C73"); line.setAttribute("stroke-width", "2.5"); line.setAttribute("points", coords);
      svg.append(line);
      var minLabel = document.createElementNS(ns, "text");
      minLabel.setAttribute("x", "48"); minLabel.setAttribute("y", "204"); minLabel.setAttribute("text-anchor", "end"); minLabel.setAttribute("fill", "#5d6d69"); minLabel.setAttribute("font-size", "12");
      minLabel.textContent = num(min);
      var maxLabel = document.createElementNS(ns, "text");
      maxLabel.setAttribute("x", "48"); maxLabel.setAttribute("y", "36"); maxLabel.setAttribute("text-anchor", "end"); maxLabel.setAttribute("fill", "#5d6d69"); maxLabel.setAttribute("font-size", "12");
      maxLabel.textContent = num(max);
      svg.append(minLabel, maxLabel);
    }
    function deviceCard(device) {
      var card = el("article", "card device-card");
      var header = el("header");
      var title = el("div");
      title.append(el("h3", "", device.name || device.device_id));
      title.append(el("div", "meta", device.device_id));
      header.append(title, badge(deviceStatus(device)));
      var body = el("div", "meta", (KINDS[device.sensor_kind] || device.sensor_kind || "\u5C1A\u65E0\u4F20\u611F\u5668") + (device.sensor_model ? " \xB7 " + device.sensor_model : ""));
      var when = el("div", "meta", device.last_received_at ? "\u6700\u8FD1\u4E0A\u62A5 " + relative(device.last_received_at) + " \xB7 " + shanghai(new Date(device.last_received_at)) : "\u8FD8\u6CA1\u6709\u56DE\u6267");
      var counts = el("div", "meta", "\u4E8B\u4EF6 " + (device.event_count || 0) + " \xB7 \u51B2\u7A81 " + (device.open_conflicts || 0) + " \xB7 \u91CD\u590D " + (device.duplicate_acks || 0));
      card.append(header, body, when, counts);
      return card;
    }
    function renderOverviewDevices() {
      var host = $("overview-devices");
      host.replaceChildren();
      if (!state.devices.length) { host.append(empty("\u8FD8\u6CA1\u6709\u91C7\u96C6\u7AEF", "\u624B\u673A\u6253\u5F00\u5E94\u7528\u540E\u4F1A\u81EA\u52A8\u767B\u8BB0\u3002")); return; }
      state.devices.slice(0, 6).forEach(function (device) { host.append(deviceCard(device)); });
    }
    function renderDeviceTable() {
      var host = $("device-table");
      host.replaceChildren();
      if (!state.devices.length) { host.append(empty("\u8FD8\u6CA1\u6709\u91C7\u96C6\u7AEF", "\u767B\u8BB0\u4E4B\u540E\u4F1A\u51FA\u73B0\u5728\u8FD9\u5F20\u8868\u91CC\u3002")); return; }
      host.append(table(["\u540D\u79F0", "\u72B6\u6001", "\u4F20\u611F\u5668", "\u6700\u8FD1\u4E0A\u62A5", "\u4E8B\u4EF6", "\u51B2\u7A81", "\u91CD\u590D\u786E\u8BA4"], state.devices.map(function (device) {
        return { cells: [device.name + " (" + device.device_id + ")", badge(deviceStatus(device)), (KINDS[device.sensor_kind] || "\u2014") + (device.sensor_model ? " \xB7 " + device.sensor_model : ""), device.last_received_at ? relative(device.last_received_at) : "\u5C1A\u65E0\u4E0A\u62A5", device.event_count || 0, device.open_conflicts || 0, device.duplicate_acks || 0] };
      })));
    }
    function filteredEvents() {
      var type = $("filter-type").value;
      var device = $("filter-device").value;
      var range = $("filter-range").value;
      return state.events.filter(function (item) {
        var event = item.event || {};
        if (type && event.measurement_type !== type) return false;
        if (device && event.device_id !== device) return false;
        if (!within(item.server_received_at, range)) return false;
        return true;
      });
    }
    function fillFilters() {
      var type = $("filter-type");
      var device = $("filter-device");
      var typeValue = type.value;
      var deviceValue = device.value;
      type.replaceChildren(new Option("\u5168\u90E8\u7C7B\u578B", ""));
      var seen = {};
      state.events.forEach(function (item) { if (item.event) seen[item.event.measurement_type] = true; });
      Object.keys(TYPES).forEach(function (key) { if (seen[key]) type.append(new Option(TYPES[key], key)); });
      type.value = typeValue;
      device.replaceChildren(new Option("\u5168\u90E8\u8BBE\u5907", ""));
      state.devices.forEach(function (item) { device.append(new Option(item.name || item.device_id, item.device_id)); });
      if ([].some.call(device.options, function (option) { return option.value === deviceValue; })) device.value = deviceValue;
    }
    function renderRecords() {
      fillFilters();
      $("records-note").textContent = state.note || "\u6700\u8FD1 100 \u6761\u56DE\u6267\u3002\u70B9\u51FB\u4E00\u884C\u67E5\u770B\u539F\u59CB JSON\u3002";
      var rows = filteredEvents();
      var pages = Math.max(1, Math.ceil(rows.length / state.pageSize));
      if (state.page > pages) state.page = pages;
      var start = (state.page - 1) * state.pageSize;
      var slice = rows.slice(start, start + state.pageSize);
      var host = $("records");
      host.replaceChildren();
      if (!slice.length) { host.append(empty("\u6CA1\u6709\u8BB0\u5F55", "\u6362\u4E00\u4E2A\u7C7B\u578B\u3001\u8BBE\u5907\u6216\u65F6\u95F4\u8303\u56F4\u3002")); }
      else host.append(table(["\u65F6\u95F4", "\u8BBE\u5907", "\u5185\u5BB9", "\u8FD0\u884C\u72B6\u6001"], slice.map(function (item) {
        var event = item.event || {};
        var when = item.server_received_at ? relative(item.server_received_at) + " \xB7 " + shanghai(new Date(item.server_received_at)) : "\u65F6\u95F4\u672A\u77E5";
        return { cells: [when, event.device_id || "", humanValue(event), OPS[event.operating_state] || event.operating_state || ""], onClick: function () { openDrawer(item); } };
      })));
      $("page-label").textContent = rows.length ? "\u7B2C " + state.page + " / " + pages + " \u9875 \xB7 \u5171 " + rows.length + " \u6761" : "\u6CA1\u6709\u5339\u914D\u7684\u8BB0\u5F55";
      $("prev").disabled = state.page <= 1;
      $("next").disabled = state.page >= pages;
    }
    function openDrawer(item) {
      var event = item.event || {};
      $("drawer-title").textContent = humanValue(event);
      $("drawer-sub").textContent = (event.device_id || "") + " \xB7 " + relative(item.server_received_at) + " \xB7 " + (item.server_received_at ? shanghai(new Date(item.server_received_at)) : "");
      $("drawer-hash").textContent = "payload_hash " + (item.payload_hash || "");
      var payload = { server_received_at: item.server_received_at, payload_hash: item.payload_hash, event: event };
      if (item.canonical_json) payload.canonical_json = item.canonical_json;
      $("drawer-json").textContent = JSON.stringify(payload, null, 2);
      $("drawer").hidden = false;
    }
    function rateText(rate) {
      if (!rate || rate.status !== "computed" || rate.value == null) return "\u2014";
      var pct = Math.round(rate.value * 1000) / 10;
      return (pct % 1 === 0 ? String(pct.toFixed(0)) : String(pct)) + "%";
    }
    function rateCard(title, rate) {
      var box = el("div", "stat");
      box.append(el("b", "", rateText(rate)), el("span", "", title + (rate && rate.status !== "computed" ? " \xB7 \u5C1A\u4E0D\u53EF\u8BA1\u7B97" : "")));
      if (rate && rate.reason && rate.status !== "computed") box.append(el("span", "", rate.reason));
      else if (rate) box.append(el("span", "", (rate.numerator || 0) + " / " + (rate.denominator || 0)));
      return box;
    }
    function renderRQ() {
      var host = $("rq");
      host.replaceChildren();
      if (!state.rq) { host.append(empty("\u6B63\u5728\u8BFB\u53D6\u7814\u7A76\u6307\u6807", "RQ1 \u5230 RQ4 \u6765\u81EA\u5BFC\u51FA\u63A5\u53E3\u3002")); return; }
      var specs = [
        ["RQ1 \u63D0\u9192", state.rq.rq1, [["\u786E\u8BA4\u7387", "ack_rate"], ["\u6F0F\u62A5\u7387", "miss_rate"], ["\u89C2\u5BDF\u8005\u9001\u8FBE\u7387", "delivery_rate"]]],
        ["RQ2 \u5BF9\u7167", state.rq.rq2, [["\u53EC\u56DE\u7387", "recall"], ["\u7279\u5F02\u5EA6", "specificity"]]],
        ["RQ3 \u56DE\u6267", state.rq.rq3, [["\u91CD\u590D\u5C1D\u8BD5\u7387", "duplicate_attempt_rate"]]],
        ["RQ4 \u53EF\u7528\u6027", state.rq.rq4, []]
      ];
      specs.forEach(function (spec) {
        var report = spec[1] || {};
        var card = el("article", "panel");
        var head = el("div", "panel-head");
        head.append(el("h2", "", spec[0]));
        var status = report.ack_rate || report.recall || report.duplicate_attempt_rate || (report.sus && report.sus[0]);
        if (status && status.status) head.append(badge(status.status === "computed" ? { cls: "ok", text: "\u5DF2\u8BA1\u7B97" } : { cls: "wait", text: "\u5C1A\u4E0D\u53EF\u8BA1\u7B97" }));
        else head.append(badge({ cls: "neutral", text: "\u6C47\u603B" }));
        card.append(head);
        var grid = el("div", "rq-stats");
        spec[2].forEach(function (pair) { grid.append(rateCard(pair[0], report[pair[1]])); });
        if (spec[0].indexOf("RQ2") === 0 && report.confusion) {
          var unmatched = el("div", "stat");
          unmatched.append(el("b", "", String(report.unmatched_ground_truth || 0)), el("span", "", "\u672A\u5339\u914D\u5BF9\u7167\uFF0C\u4E0D\u8BA1\u5165\u9519\u8BEF"));
          grid.append(unmatched);
        }
        if (spec[0].indexOf("RQ3") === 0) {
          [["\u5DF2\u5B58\u50A8", report.stored_events], ["\u91CD\u590D\u786E\u8BA4", report.duplicate_acks], ["\u51B2\u7A81", report.conflicts]].forEach(function (pair) {
            var box = el("div", "stat");
            box.append(el("b", "", String(pair[1] || 0)), el("span", "", pair[0]));
            grid.append(box);
          });
        }
        if (spec[0].indexOf("RQ4") === 0) {
          var tasks = report.task_dispositions || {};
          Object.keys(tasks).forEach(function (key) {
            var box = el("div", "stat");
            box.append(el("b", "", String(tasks[key])), el("span", "", key));
            grid.append(box);
          });
          (report.sus || []).forEach(function (item) {
            var box = el("div", "stat");
            box.append(el("b", "", item.score == null ? "\u2014" : String(item.score)), el("span", "", "SUS " + (item.status === "computed" ? "\u5DF2\u8BA1\u7B97" : "\u5C1A\u4E0D\u53EF\u8BA1\u7B97" + (item.reason ? " \xB7 " + item.reason : ""))));
            grid.append(box);
          });
        }
        card.append(grid, el("p", "sub", report.note || ""));
        host.append(card);
      });
    }
    function ensureRQ() {
      if (state.rq) { renderRQ(); return; }
      $("rq").replaceChildren(empty("\u6B63\u5728\u8BFB\u53D6", "\u7A0D\u7B49\u4E00\u4E0B\u3002"));
      Promise.all(["rq1", "rq2", "rq3", "rq4"].map(function (name) { return api("/api/v1/exports/" + name + ".json"); })).then(function (rows) {
        state.rq = { rq1: rows[0], rq2: rows[1], rq3: rows[2], rq4: rows[3] };
        renderRQ();
      }).catch(showError);
    }
    function renderConflicts() {
      var host = $("conflicts");
      var kpi = $("recon-kpi");
      kpi.replaceChildren();
      var counts = state.recon && state.recon.counts ? state.recon.counts : null;
      var cards = counts ? [["\u5DF2\u5B58\u50A8", counts.stored_events], ["\u91CD\u590D\u786E\u8BA4", counts.duplicate_acks], ["\u51B2\u7A81", counts.conflicts]] : [["\u51B2\u7A81\u8BB0\u5F55", state.conflicts.length]];
      cards.forEach(function (item) {
        var card = el("article", "card");
        card.append(el("div", "label", item[0]), el("div", "value", String(item[1] == null ? 0 : item[1])), el("div", "hint", "\u670D\u52A1\u5668\u56DE\u6267\uFF0C\u4E0D\u662F\u4E22\u5931\u4F30\u8BA1"));
        kpi.append(card);
      });
      host.replaceChildren();
      var rows = (state.recon && state.recon.conflicts) || state.conflicts;
      if (!rows.length) { host.append(empty("\u6CA1\u6709\u51B2\u7A81", "\u76F8\u540C\u5185\u5BB9\u7684\u91CD\u590D\u4E0A\u4F20\u4E0D\u4F1A\u51FA\u73B0\u5728\u8FD9\u91CC\u3002")); return; }
      host.append(table(["\u65F6\u95F4", "\u91C7\u96C6\u7AEF", "event_id", "\u5DF2\u4FDD\u7559\u54C8\u5E0C", "\u540E\u5230\u54C8\u5E0C"], rows.map(function (row) {
        return { cells: [relative(row.at), row.device_id, row.event_id, row.stored_hash, row.presented_hash] };
      })));
    }
    function ensureRecon() {
      if (state.recon) { renderConflicts(); return; }
      api("/api/v1/exports/reconciliation.json").then(function (data) { state.recon = data; renderConflicts(); }).catch(showError);
    }
    function renderExports() {
      var items = [
        ["/api/v1/exports/events.csv", "events.csv", "\u4E8B\u4EF6 CSV", "\u56DE\u6267\u65F6\u95F4\u3001\u8BBE\u5907\u548C\u6570\u503C"],
        ["/api/v1/exports/events.json", "events.json", "\u4E8B\u4EF6 JSON", "\u539F\u59CB\u56DE\u6267\u65E5\u5FD7"],
        ["/api/v1/exports/reconciliation.json", "reconciliation.json", "\u5BF9\u8D26 JSON", "\u5B58\u50A8\u3001\u91CD\u590D\u548C\u51B2\u7A81\u8BA1\u6570"],
        ["/api/v1/exports/rq1.json", "rq1.json", "RQ1 JSON", "\u63D0\u9192\u786E\u8BA4\u4E0E\u9001\u8FBE"],
        ["/api/v1/exports/rq2.json", "rq2.json", "RQ2 JSON", "\u5BF9\u7167\u6DF7\u6DC6\u77E9\u9635"],
        ["/api/v1/exports/rq3.json", "rq3.json", "RQ3 JSON", "\u4E0A\u4F20\u56DE\u6267"],
        ["/api/v1/exports/rq4.json", "rq4.json", "RQ4 JSON", "\u4EFB\u52A1\u4E0E SUS"]
      ];
      var host = $("exports");
      host.replaceChildren();
      items.forEach(function (item) {
        var button = el("button", "panel");
        button.type = "button";
        button.append(document.createTextNode(item[2]), el("small", "", item[3]));
        button.addEventListener("click", function () { download(item[0], item[1]); });
        host.append(button);
      });
    }
    function download(path, filename) {
      fetch(path, { headers: { Authorization: "Bearer " + state.token } }).then(function (response) {
        if (!response.ok) throw new Error("\u5BFC\u51FA\u5931\u8D25");
        return response.blob();
      }).then(function (blob) {
        var link = document.createElement("a");
        link.href = URL.createObjectURL(blob);
        link.download = filename;
        link.click();
      }).catch(showError);
    }
    function refresh() {
      clearError();
      setLoading(true);
      Promise.all([
        api("/api/v1/dashboard/devices"),
        api("/api/v1/dashboard/events"),
        api("/api/v1/dashboard/conflicts")
      ]).then(function (rows) {
        state.devices = Array.isArray(rows[0]) ? rows[0] : [];
        state.events = rows[1] && Array.isArray(rows[1].events) ? rows[1].events : [];
        state.note = rows[1] && rows[1].note ? rows[1].note : "";
        state.conflicts = Array.isArray(rows[2]) ? rows[2] : [];
        if (!state.seriesTouched) {
          state.seriesType = chooseSeriesType(state.events);
          $("series-type").value = state.seriesType;
        }
        return api("/api/v1/dashboard/series?type=" + encodeURIComponent(state.seriesType));
      }).then(function (series) {
        state.series = Array.isArray(series) ? series : [];
        state.updatedAt = new Date();
        state.rq = null;
        state.recon = null;
        renderAll();
        if (state.view === "research") ensureRQ();
        if (state.view === "reconcile") ensureRecon();
      }).catch(showError).then(function () { setLoading(false); });
    }
    function logout() {
      sessionStorage.removeItem("bylw_token");
      sessionStorage.removeItem("bylw_role");
      sessionStorage.removeItem("bylw_user");
      state.token = "";
      $("app").hidden = true;
      $("login-screen").hidden = false;
      $("user-menu").hidden = true;
    }
    function signedIn(data) {
      state.token = data.token;
      state.role = data.role || "";
      state.username = data.username || "";
      sessionStorage.setItem("bylw_token", state.token);
      sessionStorage.setItem("bylw_role", state.role);
      sessionStorage.setItem("bylw_user", state.username);
      $("login-screen").hidden = true;
      $("app").hidden = false;
      paintUser();
      showView("overview");
      refresh();
    }
    $("login-form").addEventListener("submit", function (event) {
      event.preventDefault();
      var form = new FormData(event.target);
      var error = $("login-error");
      error.style.display = "none";
      fetch("/api/v1/auth/login", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ username: form.get("username"), password: form.get("password") }) }).then(function (response) {
        return response.json().then(function (data) {
          if (!response.ok) throw new Error(data.error || "\u767B\u5F55\u5931\u8D25");
          signedIn(data);
        });
      }).catch(function (err) { error.style.display = "block"; error.textContent = err.message || "\u767B\u5F55\u5931\u8D25"; });
    });
    $("nav").addEventListener("click", function (event) {
      var button = event.target.closest("button");
      if (button && button.getAttribute("data-view")) showView(button.getAttribute("data-view"));
    });
    document.body.addEventListener("click", function (event) {
      var jump = event.target.closest("[data-jump]");
      if (jump) showView(jump.getAttribute("data-jump"));
    });
    $("menu").addEventListener("click", function () { $("sidebar").classList.toggle("open"); $("backdrop").classList.toggle("show"); });
    $("backdrop").addEventListener("click", function () { $("sidebar").classList.remove("open"); $("backdrop").classList.remove("show"); });
    $("refresh").addEventListener("click", refresh);
    $("user-btn").addEventListener("click", function () { $("user-menu").hidden = !$("user-menu").hidden; });
    $("logout").addEventListener("click", logout);
    $("series-type").addEventListener("change", function () { state.seriesTouched = true; state.seriesType = $("series-type").value; refresh(); });
    $("range").addEventListener("click", function (event) {
      var button = event.target.closest("button");
      if (!button) return;
      state.range = button.getAttribute("data-range");
      $("range").querySelectorAll("button").forEach(function (item) { item.classList.toggle("on", item === button); });
      renderChart();
    });
    ["filter-type", "filter-device", "filter-range"].forEach(function (id) { $(id).addEventListener("change", function () { state.page = 1; renderRecords(); }); });
    $("prev").addEventListener("click", function () { if (state.page > 1) { state.page--; renderRecords(); } });
    $("next").addEventListener("click", function () { state.page++; renderRecords(); });
    $("drawer-close").addEventListener("click", function () { $("drawer").hidden = true; });
    $("drawer").addEventListener("click", function (event) { if (event.target === $("drawer")) $("drawer").hidden = true; });
    $("device-form").addEventListener("submit", function (event) {
      event.preventDefault();
      var form = new FormData(event.target);
      api("/api/v1/admin/devices", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ device_id: form.get("device_id"), name: form.get("name") }) }).then(function () {
        $("pair-form").elements.device_id.value = form.get("device_id");
        refresh();
      }).catch(showError);
    });
    $("pair-form").addEventListener("submit", function (event) {
      event.preventDefault();
      var id = String(new FormData(event.target).get("device_id") || "");
      api("/api/v1/admin/devices/" + encodeURIComponent(id) + "/pairing-codes", { method: "POST" }).then(function (data) {
        $("pair-code").textContent = data.code;
        $("pair-note").textContent = "\u91C7\u96C6\u7AEF " + data.device_id + " \xB7 10 \u5206\u949F\u5185\u6709\u6548 \xB7 \u53EA\u80FD\u4F7F\u7528\u4E00\u6B21";
      }).catch(showError);
    });
    renderExports();
    if (token()) {
      state.token = token();
      state.role = sessionStorage.getItem("bylw_role") || "";
      state.username = sessionStorage.getItem("bylw_user") || "";
      $("login-screen").hidden = true;
      $("app").hidden = false;
      paintUser();
      refresh();
    }
  <\/script>
</body>
</html>
`;

// src/json.ts
var Ordered = class {
  constructor(entries) {
    this.entries = entries;
  }
  entries;
  static {
    __name(this, "Ordered");
  }
};
var Raw = class {
  constructor(text2) {
    this.text = text2;
  }
  text;
  static {
    __name(this, "Raw");
  }
};
function jsonString(value) {
  let out = '"';
  for (const ch of value) {
    const code = ch.codePointAt(0) ?? 0;
    switch (ch) {
      case '"':
        out += '\\"';
        break;
      case "\\":
        out += "\\\\";
        break;
      case "\b":
        out += "\\b";
        break;
      case "\f":
        out += "\\f";
        break;
      case "\n":
        out += "\\n";
        break;
      case "\r":
        out += "\\r";
        break;
      case "	":
        out += "\\t";
        break;
      case "&":
        out += "\\u0026";
        break;
      case "<":
        out += "\\u003c";
        break;
      case ">":
        out += "\\u003e";
        break;
      default:
        if (code < 32 || code === 8232 || code === 8233) {
          out += "\\u" + code.toString(16).padStart(4, "0");
        } else {
          out += ch;
        }
    }
  }
  out += '"';
  return out;
}
__name(jsonString, "jsonString");
function formatNumber(value, canonical) {
  if (!Number.isFinite(value)) {
    throw new Error("values cannot contain NaN or infinity");
  }
  if (Object.is(value, -0)) {
    return "0";
  }
  const whole = value === Math.trunc(value) && Math.abs(value) < 1e15;
  if (canonical) {
    if (whole) {
      return String(Math.trunc(value));
    }
    return value.toFixed(4);
  }
  return JSON.stringify(value);
}
__name(formatNumber, "formatNumber");
function encode(value, canonical = false) {
  if (value === null || value === void 0) {
    return "null";
  }
  if (typeof value === "boolean") {
    return value ? "true" : "false";
  }
  if (typeof value === "number") {
    return formatNumber(value, canonical);
  }
  if (typeof value === "string") {
    return jsonString(value);
  }
  if (value instanceof Raw) {
    return value.text;
  }
  if (value instanceof Ordered) {
    const parts = value.entries.filter(([, item]) => item !== void 0).map(([key, item]) => jsonString(key) + ":" + encode(item, canonical));
    return "{" + parts.join(",") + "}";
  }
  if (Array.isArray(value)) {
    return "[" + value.map((item) => encode(item, canonical)).join(",") + "]";
  }
  if (typeof value === "object") {
    const entries = Object.entries(value).filter(([, item]) => item !== void 0);
    entries.sort((a, b) => a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0);
    return "{" + entries.map(([key, item]) => jsonString(key) + ":" + encode(item, canonical)).join(",") + "}";
  }
  throw new Error("unsupported value type");
}
__name(encode, "encode");
function jsonBody(value) {
  return encode(value) + "\n";
}
__name(jsonBody, "jsonBody");
function csvField(value) {
  if (/[",\n\r]/.test(value)) {
    return `"${value.replaceAll('"', '""')}"`;
  }
  return value;
}
__name(csvField, "csvField");
function csvLine(fields) {
  return fields.map(csvField).join(",") + "\n";
}
__name(csvLine, "csvLine");

// src/metrics.ts
function ratio(num2, den, emptyReason) {
  if (den === 0) {
    return { status: "not_evaluable", value: null, numerator: num2, denominator: 0, reason: emptyReason };
  }
  return { status: "computed", value: num2 / den, numerator: num2, denominator: den };
}
__name(ratio, "ratio");
function str(value) {
  return typeof value === "string" ? value : "";
}
__name(str, "str");
function asFloat(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}
__name(asFloat, "asFloat");
function truthy(value) {
  return value === "true" || value === "1" || value === "yes" || value === "perceived";
}
__name(truthy, "truthy");
function truthyValue(value) {
  if (typeof value === "boolean") {
    return value;
  }
  if (typeof value === "string") {
    return truthy(value);
  }
  return false;
}
__name(truthyValue, "truthyValue");
function summarizeRQ1(events, ledger) {
  const counts2 = {
    scheduled: 0,
    command_logged: 0,
    ack_timely: 0,
    ack_delayed: 0,
    missed: 0,
    censored: 0
  };
  const latest = /* @__PURE__ */ new Map();
  for (const event of events) {
    if (event.measurement_type !== "reminder") {
      continue;
    }
    let key = str(event.values.schedule_id);
    if (key === "") {
      key = str(event.values.match_key);
    }
    if (key === "") {
      continue;
    }
    const prev = latest.get(key);
    if (!prev || event.monotonic_us >= prev.monotonic_us) {
      latest.set(key, event);
    }
  }
  for (const event of latest.values()) {
    switch (str(event.values.disposition)) {
      case "SCHEDULED":
        counts2.scheduled++;
        break;
      case "COMMAND_LOGGED":
        counts2.command_logged++;
        break;
      case "ACK_TIMELY":
        counts2.ack_timely++;
        break;
      case "ACK_DELAYED":
        counts2.ack_delayed++;
        break;
      case "MISSED":
        counts2.missed++;
        break;
      case "CENSORED":
        counts2.censored++;
        break;
      default:
        break;
    }
  }
  const acked = counts2.ack_timely + counts2.ack_delayed;
  const fired = counts2.command_logged + acked + counts2.missed + counts2.censored;
  let observerEligible = 0;
  let observerPerceived = 0;
  for (const row of ledger) {
    if (row.reference_type === "reminder_eligible" && truthy(row.reference_value)) {
      observerEligible++;
    }
    if (row.reference_type === "reminder_perceived" && truthy(row.reference_value)) {
      observerPerceived++;
    }
  }
  return {
    note: "Device-journal rates use reminder events only. Observer delivery rate stays not_evaluable until an independent ledger has eligible rows. Empty output is not a measured zero performance.",
    device_journal: counts2,
    observer: { eligible: observerEligible, perceived: observerPerceived },
    ack_rate: ratio(acked, fired, "no fired reminder instances in the device journal"),
    miss_rate: ratio(counts2.missed, fired, "no fired reminder instances in the device journal"),
    delivery_rate: ratio(observerPerceived, observerEligible, "no observer-marked eligible reminders")
  };
}
__name(summarizeRQ1, "summarizeRQ1");
function family(measurementType) {
  switch (measurementType) {
    case "worn_state":
      return "worn";
    case "data_gap":
      return "data_gap";
    case "care_attention":
      return "care_attention";
    default:
      return measurementType;
  }
}
__name(family, "family");
function positiveEvent(event) {
  switch (event.measurement_type) {
    case "worn_state":
      return truthyValue(event.values.worn);
    case "data_gap":
      return truthyValue(event.values.gap);
    case "care_attention":
      return str(event.values.flag) === "CARE_ATTENTION_OVERDUE";
    default:
      return false;
  }
}
__name(positiveEvent, "positiveEvent");
function summarizeRQ2(events, ledger) {
  const index = /* @__PURE__ */ new Map();
  for (const event of events) {
    const match2 = str(event.values.match_key);
    if (match2 === "") {
      continue;
    }
    const key = `${event.device_id}|${match2}|${family(event.measurement_type)}`;
    const prev = index.get(key);
    if (!prev || event.monotonic_us >= prev.monotonic_us) {
      index.set(key, event);
    }
  }
  let tp = 0;
  let tn = 0;
  let fp = 0;
  let fn = 0;
  let unmatched = 0;
  for (const row of ledger) {
    if (row.reference_type !== "worn" && row.reference_type !== "data_gap" && row.reference_type !== "care_attention") {
      continue;
    }
    const event = index.get(`${row.device_id}|${row.match_key}|${row.reference_type}`);
    if (!event) {
      unmatched++;
      continue;
    }
    const got = positiveEvent(event);
    const want = truthy(row.reference_value);
    if (want && got) {
      tp++;
    } else if (!want && !got) {
      tn++;
    } else if (!want && got) {
      fp++;
    } else {
      fn++;
    }
  }
  return {
    note: "Confusion counts exist only for ground-truth rows that share device_id and match_key with a device event. Unmatched rows are not treated as errors.",
    confusion: { tp, tn, fp, fn },
    unmatched_ground_truth: unmatched,
    recall: ratio(tp, tp + fn, "no positive matched ground-truth rows"),
    specificity: ratio(tn, tn + fp, "no negative matched ground-truth rows")
  };
}
__name(summarizeRQ2, "summarizeRQ2");
function summarizeRQ3(stored, duplicates, conflicts2) {
  const attempts = stored + duplicates + conflicts2;
  return {
    note: "Counts are server ingest attempts. Pending events that never left the phone are not visible here. This is not a data-loss estimate.",
    stored_events: stored,
    duplicate_acks: duplicates,
    conflicts: conflicts2,
    duplicate_attempt_rate: ratio(duplicates, attempts, "no ingest attempts"),
    pending_on_server: "not_observable"
  };
}
__name(summarizeRQ3, "summarizeRQ3");
function itoa(n) {
  return n === 10 ? "10" : String(n);
}
__name(itoa, "itoa");
function scoreSUS(event) {
  const result = {
    device_id: event.device_id,
    match_key: str(event.values.match_key),
    score: null,
    status: "not_evaluable"
  };
  let sum = 0;
  for (let i = 1; i <= 10; i++) {
    const key = "q" + itoa(i);
    if (!(key in event.values)) {
      result.reason = "missing item";
      return result;
    }
    const n = Math.trunc(asFloat(event.values[key]));
    if (n < 1 || n > 5) {
      result.reason = "item outside 1..5";
      return result;
    }
    sum += i % 2 === 1 ? n - 1 : 5 - n;
  }
  result.score = 2.5 * sum;
  result.status = "computed";
  return result;
}
__name(scoreSUS, "scoreSUS");
function summarizeRQ4(events) {
  const tasks = { unassisted: 0, assisted: 0, abandoned: 0, not_started: 0 };
  const scores = [];
  for (const event of events) {
    if (event.measurement_type === "usability_task") {
      const disposition = str(event.values.disposition);
      if (disposition in tasks) {
        tasks[disposition]++;
      }
    }
    if (event.measurement_type === "sus") {
      scores.push(scoreSUS(event));
    }
  }
  return {
    note: "SUS is scored only when q1 through q10 are all present. A missing item does not become a total. Task counts are logged dispositions, not a completed ethics study.",
    task_dispositions: tasks,
    sus: scores
  };
}
__name(summarizeRQ4, "summarizeRQ4");

// src/time.ts
var RFC3339 = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|([+-])(\d{2}):(\d{2}))$/;
function parseRFC3339(raw2) {
  const match2 = RFC3339.exec(raw2);
  if (!match2) {
    return null;
  }
  const year = Number(match2[1]);
  const month = Number(match2[2]);
  const day = Number(match2[3]);
  const hour = Number(match2[4]);
  const minute = Number(match2[5]);
  const second = Number(match2[6]);
  if (month < 1 || month > 12 || hour > 23 || minute > 59 || second > 59) {
    return null;
  }
  const frac = match2[7] ? Number(`0.${match2[7]}`) : 0;
  const millis = Math.round(frac * 1e3);
  let offsetMin = 0;
  if (match2[8] !== "Z") {
    const sign = match2[9] === "+" ? 1 : -1;
    offsetMin = sign * (Number(match2[10]) * 60 + Number(match2[11]));
  }
  if (Math.abs(offsetMin) > 14 * 60) {
    return null;
  }
  const utc = Date.UTC(year, month - 1, day, hour, minute, second, millis) - offsetMin * 6e4;
  const wall = new Date(utc + offsetMin * 6e4);
  if (wall.getUTCFullYear() !== year || wall.getUTCMonth() !== month - 1 || wall.getUTCDate() !== day || wall.getUTCHours() !== hour || wall.getUTCMinutes() !== minute || wall.getUTCSeconds() !== second) {
    return null;
  }
  return new Date(utc);
}
__name(parseRFC3339, "parseRFC3339");
function formatRFC3339(date) {
  return date.toISOString().slice(0, 19) + "Z";
}
__name(formatRFC3339, "formatRFC3339");
function formatRFC3339Nano(date) {
  const iso = date.toISOString();
  const frac = iso.slice(20, 23).replace(/0+$/, "");
  const head = iso.slice(0, 19);
  return frac ? `${head}.${frac}Z` : `${head}Z`;
}
__name(formatRFC3339Nano, "formatRFC3339Nano");
function nowNano(date = /* @__PURE__ */ new Date()) {
  return formatRFC3339Nano(date);
}
__name(nowNano, "nowNano");
function parseGoTime(raw2) {
  return parseRFC3339(raw2);
}
__name(parseGoTime, "parseGoTime");
var DURATION = /[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:ns|us|µs|μs|ms|s|m|h)/g;
var UNIT_MS = {
  ns: 1e-6,
  us: 1e-3,
  \u00B5s: 1e-3,
  \u03BCs: 1e-3,
  ms: 1,
  s: 1e3,
  m: 6e4,
  h: 36e5
};
function parseDuration(raw2) {
  const text2 = raw2.trim();
  if (!text2) {
    return null;
  }
  const parts = text2.match(DURATION);
  if (!parts || parts.join("") !== text2) {
    return null;
  }
  let total = 0;
  for (const part of parts) {
    const split = /^(.*?)(ns|us|µs|μs|ms|s|m|h)$/.exec(part);
    if (!split) {
      return null;
    }
    const unit = UNIT_MS[split[2]];
    total += Number(split[1]) * unit;
  }
  if (!Number.isFinite(total) || total < 0) {
    return null;
  }
  return total;
}
__name(parseDuration, "parseDuration");
var DEFAULT_STALE_MS = 15 * 60 * 1e3;

// src/schema.ts
var SCHEMA_VERSION = "bylw-measure/1";
var KINDS = ["blood_pressure", "heart_rate", "ring", "collector"];
var TYPES = [
  "blood_pressure",
  "heart_rate",
  "steps",
  "spo2",
  "sleep",
  "sleep_session",
  "stress",
  "hrv",
  "temperature",
  "operating_state",
  "reminder",
  "care_attention",
  "worn_state",
  "data_gap",
  "usability_task",
  "sus",
  "raw_event",
  "gesture"
];
var CLOCKS = ["UNSET", "NTP_SYNCED", "HOLDOVER", "INVALID"];
var OPS = ["NOMINAL", "BLE_DISCONNECTED", "NETWORK_DEGRADED", "AUTH_FAILURE", "CLOCK_DEGRADED"];
var SchemaError = class extends Error {
  static {
    __name(this, "SchemaError");
  }
};
function token(value) {
  if (value.length < 1 || value.length > 128) {
    return false;
  }
  return /^[A-Za-z0-9._-]+$/.test(value);
}
__name(token, "token");
function oneOf(value, allowed) {
  return allowed.includes(value);
}
__name(oneOf, "oneOf");
function normalizeWallClock(raw2) {
  if (raw2 == null || raw2.trim() === "") {
    return null;
  }
  const parsed = parseRFC3339(raw2.trim());
  if (!parsed) {
    throw new SchemaError(`wall_time_utc: parsing time ${JSON.stringify(raw2.trim())} as "2006-01-02T15:04:05Z07:00": cannot parse`);
  }
  return formatRFC3339(parsed);
}
__name(normalizeWallClock, "normalizeWallClock");
function prepare(event) {
  const wall = normalizeWallClock(event.wall_time_utc);
  return {
    ...event,
    schema_version: event.schema_version === "" ? SCHEMA_VERSION : event.schema_version,
    wall_time_utc: wall,
    values: event.values ?? {}
  };
}
__name(prepare, "prepare");
function validate(event) {
  if (event.schema_version !== SCHEMA_VERSION) {
    throw new SchemaError(`schema_version must be ${SCHEMA_VERSION}`);
  }
  if (!token(event.event_id) || !token(event.device_id) || !token(event.session_id)) {
    throw new SchemaError("event_id, device_id, and session_id must be path-safe tokens");
  }
  if (!token(event.sensor_address) || !token(event.sensor_kind)) {
    throw new SchemaError("sensor_address and sensor_kind must be path-safe tokens");
  }
  if (event.sensor_model.length > 80 || event.unit.length > 16 || event.unit === "") {
    throw new SchemaError("unit is required and model/unit lengths are limited");
  }
  if (event.monotonic_us < 0) {
    throw new SchemaError("monotonic_us must be >= 0");
  }
  if (!oneOf(event.clock_state, CLOCKS)) {
    throw new SchemaError("clock_state is invalid");
  }
  if (!oneOf(event.operating_state, OPS)) {
    throw new SchemaError("operating_state is invalid");
  }
  if (!oneOf(event.sensor_kind, KINDS)) {
    throw new SchemaError("sensor_kind is invalid");
  }
  if (!oneOf(event.measurement_type, TYPES)) {
    throw new SchemaError("measurement_type is invalid");
  }
  const timed = event.clock_state === "NTP_SYNCED" || event.clock_state === "HOLDOVER";
  if (timed && event.wall_time_utc == null) {
    throw new SchemaError("wall_time_utc is required when the clock is NTP_SYNCED or HOLDOVER");
  }
  if (!timed && event.wall_time_utc != null) {
    throw new SchemaError("wall_time_utc must be null when the clock is UNSET or INVALID");
  }
  if (event.wall_time_utc != null && !parseRFC3339(event.wall_time_utc)) {
    throw new SchemaError("wall_time_utc: invalid RFC3339 timestamp");
  }
  if (event.values == null) {
    throw new SchemaError("values is required");
  }
}
__name(validate, "validate");
function canonicalJSON(event) {
  validate(event);
  const values = encode(event.values, true);
  const parts = [
    ["clock_state", jsonString(event.clock_state)],
    ["device_id", jsonString(event.device_id)],
    ["event_id", jsonString(event.event_id)],
    ["measurement_type", jsonString(event.measurement_type)],
    ["monotonic_us", String(Math.trunc(event.monotonic_us))],
    ["operating_state", jsonString(event.operating_state)],
    ["schema_version", jsonString(event.schema_version)],
    ["sensor_address", jsonString(event.sensor_address)],
    ["sensor_kind", jsonString(event.sensor_kind)],
    ["sensor_model", jsonString(event.sensor_model)],
    ["session_id", jsonString(event.session_id)],
    ["unit", jsonString(event.unit)],
    ["values", values],
    ["wall_time_utc", event.wall_time_utc == null ? "null" : jsonString(event.wall_time_utc)]
  ];
  let out = "{";
  parts.forEach((part, index) => {
    if (index > 0) {
      out += ",";
    }
    out += jsonString(part[0]) + ":" + part[1];
  });
  out += "}";
  return out;
}
__name(canonicalJSON, "canonicalJSON");
async function payloadHash(event) {
  const canonical = canonicalJSON(event);
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonical));
  const bytes = new Uint8Array(digest);
  let hash = "";
  for (const byte of bytes) {
    hash += byte.toString(16).padStart(2, "0");
  }
  return { hash, canonical };
}
__name(payloadHash, "payloadHash");

// src/crypto.ts
var PBKDF2_ITERATIONS = 1e4;
var MAX_ITERATIONS = 1e5;
function hex(bytes) {
  let out = "";
  for (const byte of bytes) {
    out += byte.toString(16).padStart(2, "0");
  }
  return out;
}
__name(hex, "hex");
function fromHex(value) {
  if (value.length % 2 !== 0 || !/^[0-9a-f]+$/i.test(value)) {
    return null;
  }
  const out = new Uint8Array(value.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = Number.parseInt(value.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}
__name(fromHex, "fromHex");
function randomToken() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return hex(bytes);
}
__name(randomToken, "randomToken");
function randomPairingCode() {
  const buf = new Uint32Array(1);
  const limit = 4294e6;
  let value = 0;
  do {
    crypto.getRandomValues(buf);
    value = buf[0];
  } while (value >= limit);
  return String(value % 1e6).padStart(6, "0");
}
__name(randomPairingCode, "randomPairingCode");
async function sha256Hex(value) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return hex(new Uint8Array(digest));
}
__name(sha256Hex, "sha256Hex");
async function pbkdf2(password, salt, iterations) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", hash: "SHA-256", salt, iterations },
    key,
    256
  );
  return new Uint8Array(bits);
}
__name(pbkdf2, "pbkdf2");
async function hashPassword(password) {
  const salt = new Uint8Array(16);
  crypto.getRandomValues(salt);
  const derived = await pbkdf2(password, salt, PBKDF2_ITERATIONS);
  return `pbkdf2-sha256$${PBKDF2_ITERATIONS}$${hex(salt)}$${hex(derived)}`;
}
__name(hashPassword, "hashPassword");
function timingSafeEqual(a, b) {
  if (a.length !== b.length) {
    return false;
  }
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}
__name(timingSafeEqual, "timingSafeEqual");
async function verifyPassword(password, stored) {
  const parts = stored.split("$");
  if (parts.length !== 4 || parts[0] !== "pbkdf2-sha256") {
    return false;
  }
  const iterations = Number(parts[1]);
  if (!Number.isInteger(iterations) || iterations < 1 || iterations > MAX_ITERATIONS) {
    return false;
  }
  const salt = fromHex(parts[2]);
  if (!salt || parts[3].length !== 64) {
    return false;
  }
  const derived = await pbkdf2(password, salt, iterations);
  return timingSafeEqual(hex(derived), parts[3].toLowerCase());
}
__name(verifyPassword, "verifyPassword");

// src/store.ts
function num(value) {
  return typeof value === "number" ? value : Number(value ?? 0);
}
__name(num, "num");
async function ping(db) {
  await db.prepare("SELECT 1 AS ok").first();
}
__name(ping, "ping");
async function countUsers(db) {
  const row = await db.prepare("SELECT COUNT(1) AS n FROM users").first();
  return num(row?.n);
}
__name(countUsers, "countUsers");
async function ensureAdmin(env) {
  const existing = await countUsers(env.DB);
  if (existing > 0) {
    return;
  }
  const username = env.BOOTSTRAP_ADMIN_USER ?? "";
  const password = env.BOOTSTRAP_ADMIN_PASSWORD ?? "";
  if (username === "" || password.length < 8) {
    return;
  }
  try {
    await createUser(env.DB, username, password, "admin");
    console.log(JSON.stringify({ level: "info", msg: "bootstrapped admin", username }));
  } catch (err) {
    const again = await countUsers(env.DB);
    if (again === 0) {
      throw err;
    }
  }
}
__name(ensureAdmin, "ensureAdmin");
async function createUser(db, username, password, role) {
  if (role !== "admin" && role !== "caregiver") {
    throw new Error("invalid role");
  }
  const passwordHash = await hashPassword(password);
  await db.prepare("INSERT INTO users(username, password_hash, role, created_at) VALUES (?, ?, ?, ?)").bind(username, passwordHash, role, nowNano()).run();
}
__name(createUser, "createUser");
async function login(db, username, password, ttlMs) {
  const row = await db.prepare("SELECT id, username, role, password_hash FROM users WHERE username = ?").bind(username).first();
  if (!row || !await verifyPassword(password, row.password_hash)) {
    return null;
  }
  const token2 = randomToken();
  const tokenHash = await sha256Hex(token2);
  const expires = nowNano(new Date(Date.now() + ttlMs));
  await db.prepare("INSERT INTO sessions(token_hash, user_id, expires_at) VALUES (?, ?, ?)").bind(tokenHash, row.id, expires).run();
  return { token: token2, user: { id: row.id, username: row.username, role: row.role } };
}
__name(login, "login");
async function userByToken(db, token2) {
  const row = await db.prepare(
    `SELECT u.id AS id, u.username AS username, u.role AS role, s.expires_at AS expires_at
       FROM sessions s JOIN users u ON u.id = s.user_id
       WHERE s.token_hash = ?`
  ).bind(await sha256Hex(token2)).first();
  if (!row) {
    return null;
  }
  const exp = parseGoTime(row.expires_at);
  if (!exp || Date.now() > exp.getTime()) {
    return null;
  }
  return { id: row.id, username: row.username, role: row.role };
}
__name(userByToken, "userByToken");
async function upsertDevice(db, id, name) {
  await db.prepare(
    `INSERT INTO devices(device_id, name, created_at) VALUES (?, ?, ?)
       ON CONFLICT(device_id) DO UPDATE SET name = excluded.name`
  ).bind(id, name, nowNano()).run();
}
__name(upsertDevice, "upsertDevice");
async function registerDevice(db, deviceID, name) {
  await upsertDevice(db, deviceID, name);
  const token2 = await issueDeviceToken(db, deviceID);
  if (!token2) {
    throw new Error("token failed");
  }
  return { token: token2, device_id: deviceID };
}
__name(registerDevice, "registerDevice");
async function issueDeviceToken(db, deviceID) {
  const row = await db.prepare("SELECT COUNT(1) AS n FROM devices WHERE device_id = ?").bind(deviceID).first();
  if (num(row?.n) === 0) {
    return null;
  }
  const token2 = randomToken();
  await db.prepare("INSERT INTO device_tokens(token_hash, device_id, created_at) VALUES (?, ?, ?)").bind(await sha256Hex(token2), deviceID, nowNano()).run();
  return token2;
}
__name(issueDeviceToken, "issueDeviceToken");
async function deviceByToken(db, token2) {
  const row = await db.prepare("SELECT device_id, revoked_at FROM device_tokens WHERE token_hash = ?").bind(await sha256Hex(token2)).first();
  if (!row || row.revoked_at) {
    return null;
  }
  return row.device_id;
}
__name(deviceByToken, "deviceByToken");
async function issuePairingCode(db, deviceID) {
  const row = await db.prepare("SELECT COUNT(1) AS n FROM devices WHERE device_id = ?").bind(deviceID).first();
  if (num(row?.n) === 0) {
    return null;
  }
  const created = nowNano();
  const expires = nowNano(new Date(Date.now() + 10 * 60 * 1e3));
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = randomPairingCode();
    try {
      await db.prepare("INSERT INTO pairing_codes(code, device_id, expires_at, created_at) VALUES (?, ?, ?, ?)").bind(code, deviceID, expires, created).run();
      return { code, expires_at: expires };
    } catch (err) {
      const message = String(err);
      if (!message.toLowerCase().includes("unique")) {
        throw err;
      }
    }
  }
  throw new Error("pairing code collision");
}
__name(issuePairingCode, "issuePairingCode");
async function redeemPairingCode(db, code) {
  const row = await db.prepare("SELECT device_id, expires_at, used_at FROM pairing_codes WHERE code = ?").bind(code).first();
  if (!row || row.used_at) {
    return null;
  }
  const exp = parseGoTime(row.expires_at);
  if (!exp || Date.now() > exp.getTime()) {
    return null;
  }
  const token2 = randomToken();
  const usedAt = nowNano();
  const updated = await db.prepare("UPDATE pairing_codes SET used_at = ? WHERE code = ? AND used_at IS NULL").bind(usedAt, code).run();
  if (num(updated.meta?.changes) !== 1) {
    return null;
  }
  try {
    await db.prepare("INSERT INTO device_tokens(token_hash, device_id, created_at) VALUES (?, ?, ?)").bind(await sha256Hex(token2), row.device_id, usedAt).run();
  } catch (err) {
    await db.prepare("UPDATE pairing_codes SET used_at = NULL WHERE code = ? AND used_at = ?").bind(code, usedAt).run();
    throw err;
  }
  return { token: token2, device_id: row.device_id };
}
__name(redeemPairingCode, "redeemPairingCode");
async function ingest(db, event, hash, canonical) {
  const existing = await db.prepare("SELECT payload_hash, server_received_at FROM events WHERE device_id = ? AND event_id = ?").bind(event.device_id, event.event_id).first();
  if (!existing) {
    const received = nowNano();
    const valuesJSON = encode(event.values);
    try {
      await db.batch([
        db.prepare(
          `INSERT INTO events(device_id, event_id, payload_hash, canonical_json, server_received_at,
              measurement_type, unit, sensor_address, sensor_kind, sensor_model, monotonic_us,
              wall_time_utc, clock_state, operating_state, values_json)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
        ).bind(
          event.device_id,
          event.event_id,
          hash,
          canonical,
          received,
          event.measurement_type,
          event.unit,
          event.sensor_address,
          event.sensor_kind,
          event.sensor_model,
          event.monotonic_us,
          event.wall_time_utc,
          event.clock_state,
          event.operating_state,
          valuesJSON
        ),
        db.prepare(
          `INSERT INTO ingest_log(device_id, event_id, result, presented_hash, stored_hash, at)
             VALUES (?, ?, 'stored', ?, ?, ?)`
        ).bind(event.device_id, event.event_id, hash, hash, received)
      ]);
      return { result: "stored", payload_hash: hash, server_received_at: received };
    } catch (err) {
      const again = await db.prepare("SELECT payload_hash, server_received_at FROM events WHERE device_id = ? AND event_id = ?").bind(event.device_id, event.event_id).first();
      if (!again) {
        throw err;
      }
      return replay(db, event, hash, again.payload_hash, again.server_received_at);
    }
  }
  return replay(db, event, hash, existing.payload_hash, existing.server_received_at);
}
__name(ingest, "ingest");
async function replay(db, event, hash, storedHash, received) {
  const result = storedHash === hash ? "duplicate" : "conflict";
  const at = nowNano();
  await db.prepare(
    `INSERT INTO ingest_log(device_id, event_id, result, presented_hash, stored_hash, at)
       VALUES (?, ?, ?, ?, ?, ?)`
  ).bind(event.device_id, event.event_id, result, hash, storedHash, at).run();
  return { result, payload_hash: storedHash, server_received_at: received };
}
__name(replay, "replay");
async function getEvent(db, deviceID, eventID) {
  return db.prepare("SELECT canonical_json, payload_hash, server_received_at FROM events WHERE device_id = ? AND event_id = ?").bind(deviceID, eventID).first();
}
__name(getEvent, "getEvent");
async function listEvents(db, limit) {
  const capped = limit <= 0 || limit > 500 ? 100 : limit;
  const rows = await db.prepare(
    `SELECT canonical_json, payload_hash, server_received_at
       FROM events ORDER BY server_received_at DESC, event_id DESC LIMIT ?`
  ).bind(capped).all();
  return rows.results;
}
__name(listEvents, "listEvents");
async function listAllEvents(db) {
  const rows = await db.prepare(
    `SELECT canonical_json, payload_hash, server_received_at
       FROM events ORDER BY server_received_at ASC, event_id ASC`
  ).all();
  return rows.results;
}
__name(listAllEvents, "listAllEvents");
async function deviceStatuses(db, staleMs) {
  const devices = await db.prepare("SELECT device_id, name FROM devices ORDER BY device_id").all();
  const out = [];
  for (const device of devices.results) {
    const status = {
      device_id: device.device_id,
      name: device.name,
      last_received_at: null,
      stale: true,
      operating_state: "",
      sensor_address: "",
      sensor_kind: "",
      sensor_model: "",
      open_conflicts: 0,
      duplicate_acks: 0,
      event_count: 0
    };
    const latest = await db.prepare(
      `SELECT server_received_at, operating_state, sensor_address, sensor_kind, sensor_model
         FROM events WHERE device_id = ? ORDER BY server_received_at DESC LIMIT 1`
    ).bind(device.device_id).first();
    if (latest) {
      status.last_received_at = latest.server_received_at;
      const at = parseGoTime(latest.server_received_at);
      status.stale = !at || Date.now() - at.getTime() > staleMs;
      status.operating_state = latest.operating_state;
      status.sensor_address = latest.sensor_address;
      status.sensor_kind = latest.sensor_kind;
      status.sensor_model = latest.sensor_model;
    }
    status.event_count = num(
      (await db.prepare("SELECT COUNT(1) AS n FROM events WHERE device_id = ?").bind(device.device_id).first())?.n
    );
    status.open_conflicts = num(
      (await db.prepare("SELECT COUNT(1) AS n FROM ingest_log WHERE device_id = ? AND result = 'conflict'").bind(device.device_id).first())?.n
    );
    status.duplicate_acks = num(
      (await db.prepare("SELECT COUNT(1) AS n FROM ingest_log WHERE device_id = ? AND result = 'duplicate'").bind(device.device_id).first())?.n
    );
    out.push(status);
  }
  return out;
}
__name(deviceStatuses, "deviceStatuses");
function deviceStatusJSON(status) {
  return new Ordered([
    ["device_id", status.device_id],
    ["name", status.name],
    ["last_received_at", status.last_received_at],
    ["stale", status.stale],
    ["operating_state", status.operating_state],
    ["sensor_address", status.sensor_address],
    ["sensor_kind", status.sensor_kind],
    ["sensor_model", status.sensor_model],
    ["open_conflicts", status.open_conflicts],
    ["duplicate_acks", status.duplicate_acks],
    ["event_count", status.event_count]
  ]);
}
__name(deviceStatusJSON, "deviceStatusJSON");
async function conflicts(db, limit) {
  const capped = limit <= 0 ? 100 : limit;
  const rows = await db.prepare(
    `SELECT device_id, event_id, stored_hash, presented_hash, at
       FROM ingest_log WHERE result = 'conflict' ORDER BY id DESC LIMIT ?`
  ).bind(capped).all();
  return rows.results;
}
__name(conflicts, "conflicts");
function conflictJSON(row) {
  return new Ordered([
    ["device_id", row.device_id],
    ["event_id", row.event_id],
    ["stored_hash", row.stored_hash],
    ["presented_hash", row.presented_hash],
    ["at", row.at]
  ]);
}
__name(conflictJSON, "conflictJSON");
function seriesValue(kind, values) {
  const asFloat2 = /* @__PURE__ */ __name((value) => typeof value === "number" && Number.isFinite(value) ? value : 0, "asFloat");
  switch (kind) {
    case "blood_pressure":
      return { value: asFloat2(values.systolic), label: "systolic" };
    case "heart_rate":
      return { value: asFloat2(values.bpm), label: "bpm" };
    case "spo2":
      return { value: asFloat2(values.spo2), label: "spo2" };
    case "temperature":
      return { value: asFloat2(values.celsius), label: "celsius" };
    case "steps":
      return { value: asFloat2(values.steps), label: "steps" };
    case "stress":
      return { value: asFloat2(values.stress), label: "stress" };
    case "hrv":
      return { value: asFloat2(values.hrv_ms), label: "hrv_ms" };
    default:
      return { value: 0, label: "" };
  }
}
__name(seriesValue, "seriesValue");
async function series(db, deviceID, measurementType, limit) {
  const capped = limit <= 0 || limit > 500 ? 100 : limit;
  const query = deviceID ? `SELECT server_received_at, values_json, measurement_type FROM events WHERE measurement_type = ? AND device_id = ? ORDER BY server_received_at DESC LIMIT ?` : `SELECT server_received_at, values_json, measurement_type FROM events WHERE measurement_type = ? ORDER BY server_received_at DESC LIMIT ?`;
  const stmt = deviceID ? db.prepare(query).bind(measurementType, deviceID, capped) : db.prepare(query).bind(measurementType, capped);
  const rows = await stmt.all();
  return rows.results.map((row) => {
    let payload = {};
    try {
      const parsed = JSON.parse(row.values_json);
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        payload = parsed;
      }
    } catch {
      payload = {};
    }
    const point = seriesValue(row.measurement_type, payload);
    return { at: row.server_received_at, value: point.value, label: point.label };
  });
}
__name(series, "series");
function seriesJSON(point) {
  return new Ordered([
    ["at", point.at],
    ["value", point.value],
    ["label", point.label]
  ]);
}
__name(seriesJSON, "seriesJSON");
async function counts(db) {
  const stored = num((await db.prepare("SELECT COUNT(1) AS n FROM events").first())?.n);
  const duplicates = num(
    (await db.prepare("SELECT COUNT(1) AS n FROM ingest_log WHERE result = 'duplicate'").first())?.n
  );
  const conflictCount = num(
    (await db.prepare("SELECT COUNT(1) AS n FROM ingest_log WHERE result = 'conflict'").first())?.n
  );
  return { stored, duplicates, conflicts: conflictCount };
}
__name(counts, "counts");
async function addGroundTruth(db, row) {
  await db.prepare(
    `INSERT INTO ground_truth(device_id, match_key, reference_type, reference_value, observed_at, observer, notes, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
  ).bind(row.device_id, row.match_key, row.reference_type, row.reference_value, row.observed_at, row.observer, row.notes, nowNano()).run();
}
__name(addGroundTruth, "addGroundTruth");
async function listGroundTruth(db) {
  const rows = await db.prepare(
    `SELECT id, device_id, match_key, reference_type, reference_value, observed_at, observer, notes
       FROM ground_truth ORDER BY id`
  ).all();
  return rows.results;
}
__name(listGroundTruth, "listGroundTruth");
function groundTruthJSON(row) {
  return new Ordered([
    ["id", row.id],
    ["device_id", row.device_id],
    ["match_key", row.match_key],
    ["reference_type", row.reference_type],
    ["reference_value", row.reference_value],
    ["observed_at", row.observed_at],
    ["observer", row.observer],
    ["notes", row.notes]
  ]);
}
__name(groundTruthJSON, "groundTruthJSON");
async function evidence(db) {
  const rows = await db.prepare("SELECT device_id, measurement_type, monotonic_us, values_json FROM events ORDER BY rowid").all();
  const events = rows.results.map((row) => {
    let values = {};
    try {
      const parsed = JSON.parse(row.values_json);
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        values = parsed;
      }
    } catch {
      values = {};
    }
    return {
      device_id: row.device_id,
      measurement_type: row.measurement_type,
      monotonic_us: num(row.monotonic_us),
      values
    };
  });
  const ledgerRows = await listGroundTruth(db);
  const ledger = ledgerRows.map((row) => ({
    device_id: row.device_id,
    match_key: row.match_key,
    reference_type: row.reference_type,
    reference_value: row.reference_value
  }));
  return { events, ledger };
}
__name(evidence, "evidence");

// src/http.ts
var CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Authorization, Content-Type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS"
};
var SESSION_TTL_MS = 12 * 60 * 60 * 1e3;
var MAX_BODY = 1 << 20;
var TOKEN_NOTE = "Store this token on the collector. It is not shown again.";
var app = new Hono3();
app.use("*", async (c, next) => {
  if (c.req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS });
  }
  try {
    await ensureAdmin(c.env);
  } catch (err) {
    console.log(JSON.stringify({ level: "error", msg: "bootstrap failed", err: String(err) }));
  }
  await next();
});
app.get("/health", async (c) => {
  try {
    await ping(c.env.DB);
  } catch {
    return json(503, { status: "degraded" });
  }
  return json(200, { status: "ok", time: formatRFC3339(/* @__PURE__ */ new Date()) });
});
app.all("/", (c) => {
  if (c.req.method !== "GET" && c.req.method !== "HEAD") {
    return text("Method Not Allowed\n", 405, { Allow: "GET" });
  }
  const headers = {
    ...CORS,
    "Content-Type": "text/html; charset=utf-8",
    "Cache-Control": "no-cache"
  };
  if (c.req.method === "HEAD") {
    return new Response(null, { status: 200, headers });
  }
  return new Response(ADMIN_HTML, { status: 200, headers });
});
app.post("/api/v1/auth/login", async (c) => {
  const body = await readJSON(c.req.raw);
  if (!body.ok) {
    return json(400, { error: "invalid JSON" });
  }
  const username = typeof body.value.username === "string" ? body.value.username.trim() : "";
  const password = typeof body.value.password === "string" ? body.value.password : "";
  const session = await login(c.env.DB, username, password, SESSION_TTL_MS);
  if (!session) {
    return json(401, { error: "invalid credentials" });
  }
  return json(200, { token: session.token, role: session.user.role, username: session.user.username });
});
app.get("/api/v1/devices/me", async (c) => {
  const deviceID = await devicePrincipal(c);
  if (deviceID instanceof Response) {
    return deviceID;
  }
  return json(200, { device_id: deviceID });
});
app.post("/api/v1/devices/register", async (c) => {
  const body = await readJSON(c.req.raw);
  if (!body.ok) {
    return json(400, { error: "invalid JSON" });
  }
  const requested = typeof body.value.device_id === "string" ? body.value.device_id.trim() : "";
  const deviceID = requested === "" ? `phone-${crypto.randomUUID().replaceAll("-", "")}` : requested;
  if (!/^[A-Za-z0-9._-]{1,128}$/.test(deviceID)) {
    return json(400, { error: "device_id must be a path-safe token" });
  }
  const nameRaw = typeof body.value.name === "string" ? body.value.name.trim() : "";
  const name = nameRaw === "" ? "bylwapp" : nameRaw.slice(0, 80);
  try {
    const issued = await registerDevice(c.env.DB, deviceID, name);
    return json(201, { token: issued.token, device_id: issued.device_id, note: TOKEN_NOTE });
  } catch (err) {
    console.log(JSON.stringify({ level: "error", msg: "register failed", err: String(err) }));
    return json(500, { error: "register failed" });
  }
});
app.post("/api/v1/devices/pair", async (c) => {
  const body = await readJSON(c.req.raw);
  if (!body.ok) {
    return json(400, { error: "invalid JSON" });
  }
  const code = typeof body.value.code === "string" ? body.value.code.trim() : "";
  if (!/^\d{6}$/.test(code)) {
    return json(400, { error: "pairing code rejected" });
  }
  const issued = await redeemPairingCode(c.env.DB, code);
  if (!issued) {
    return json(400, { error: "pairing code rejected" });
  }
  return json(201, { token: issued.token, device_id: issued.device_id, note: TOKEN_NOTE });
});
app.post("/api/v1/devices/:device_id/events", async (c) => {
  const deviceID = await devicePrincipal(c);
  if (deviceID instanceof Response) {
    return deviceID;
  }
  if (c.req.param("device_id") !== deviceID) {
    return json(403, {
      error: "device token does not match the path",
      device_id: deviceID
    });
  }
  const body = await readJSON(c.req.raw);
  if (!body.ok) {
    return json(400, { error: "invalid JSON" });
  }
  const parsed = parseEvent(body.value.event);
  if (!parsed.ok) {
    return json(400, { error: parsed.error });
  }
  let event;
  try {
    event = prepare(parsed.event);
  } catch (err) {
    return json(400, { error: err instanceof Error ? err.message : "invalid event" });
  }
  if (event.device_id !== deviceID) {
    return json(400, { error: "event.device_id does not match the path" });
  }
  let hashed;
  try {
    hashed = await payloadHash(event);
  } catch (err) {
    return json(400, { error: err instanceof Error ? err.message : "invalid event" });
  }
  const presented = typeof body.value.payload_hash === "string" ? body.value.payload_hash : "";
  if (presented.trim().toLowerCase() !== hashed.hash.toLowerCase()) {
    return json(400, { error: "payload_hash does not match the canonical event" });
  }
  try {
    const outcome = await ingest(c.env.DB, event, hashed.hash, hashed.canonical);
    const status = outcome.result === "stored" ? 201 : outcome.result === "duplicate" ? 200 : 409;
    return json(status, {
      result: outcome.result,
      event_id: event.event_id,
      payload_hash: outcome.payload_hash,
      server_received_at: outcome.server_received_at
    });
  } catch (err) {
    console.log(JSON.stringify({ level: "error", msg: "ingest failed", err: String(err) }));
    return json(500, { error: "ingest failed" });
  }
});
app.get("/api/v1/devices/:device_id/events/:event_id", async (c) => {
  const deviceID = c.req.param("device_id");
  const user = await userIfAny(c);
  if (user) {
    if (user.role !== "admin" && user.role !== "caregiver") {
      return json(403, { error: "forbidden" });
    }
  } else {
    const tokenDevice = await devicePrincipal(c);
    if (tokenDevice instanceof Response) {
      return tokenDevice;
    }
    if (tokenDevice !== deviceID) {
      return json(403, { error: "device token does not match the path" });
    }
  }
  const item = await getEvent(c.env.DB, deviceID, c.req.param("event_id"));
  if (!item) {
    return json(404, { error: "not found" });
  }
  return json(200, {
    result: "stored",
    event: new Raw(item.canonical_json),
    payload_hash: item.payload_hash,
    server_received_at: item.server_received_at
  });
});
app.get("/api/v1/dashboard/events", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const items = await listEvents(c.env.DB, 100);
  return json(200, {
    note: "\u6700\u8FD1 100 \u6761\u662F\u53EF\u89C1\u6027\u89C6\u56FE\uFF0C\u4E0D\u662F\u4E22\u5931\u6E05\u5355\uFF0C\u4E5F\u4E0D\u662F\u8BBA\u6587\u7B2C\u56DB\u7AE0\u7684\u7ED3\u679C\u3002",
    events: items.map(storedEventJSON)
  });
});
app.get("/api/v1/dashboard/devices", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const items = await deviceStatuses(c.env.DB, staleAfter(c.env));
  return json(200, items.map(deviceStatusJSON));
});
app.get("/api/v1/dashboard/conflicts", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const items = await conflicts(c.env.DB, 100);
  return json(200, items.map(conflictJSON));
});
app.get("/api/v1/dashboard/series", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const kind = c.req.query("type") ?? "";
  if (kind === "") {
    return json(400, { error: "type is required" });
  }
  const points = await series(c.env.DB, c.req.query("device_id") ?? "", kind, 100);
  return json(200, points.map(seriesJSON));
});
app.get("/api/v1/exports/events.json", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const items = await listAllEvents(c.env.DB);
  return attachment(
    jsonBody({
      note: "Raw server receipt log. Not a Chapter 4 result.",
      events: items.map(storedEventJSON)
    }),
    "application/json; charset=utf-8",
    "events.json"
  );
});
app.get("/api/v1/exports/events.csv", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const items = await listAllEvents(c.env.DB);
  let body = csvLine([
    "server_received_at",
    "device_id",
    "event_id",
    "payload_hash",
    "measurement_type",
    "unit",
    "sensor_address",
    "sensor_kind",
    "sensor_model",
    "monotonic_us",
    "wall_time_utc",
    "clock_state",
    "operating_state",
    "values_json"
  ]);
  for (const item of items) {
    const event = JSON.parse(item.canonical_json);
    body += csvLine([
      item.server_received_at,
      event.device_id,
      event.event_id,
      item.payload_hash,
      event.measurement_type,
      event.unit,
      event.sensor_address,
      event.sensor_kind,
      event.sensor_model,
      String(event.monotonic_us),
      event.wall_time_utc ?? "",
      event.clock_state,
      event.operating_state,
      encode(event.values)
    ]);
  }
  return attachment(body, "text/csv; charset=utf-8", "events.csv");
});
app.get("/api/v1/exports/reconciliation.json", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const tally = await counts(c.env.DB);
  const rows = await conflicts(c.env.DB, 500);
  return json(200, {
    note: "Server-side receipt reconciliation. Duplicate and conflict counts are ingest attempts. This file does not estimate data loss and is not a Chapter 4 result.",
    counts: {
      stored_events: tally.stored,
      duplicate_acks: tally.duplicates,
      conflicts: tally.conflicts
    },
    conflicts: rows.map(conflictJSON)
  });
});
app.get("/api/v1/exports/rq1.json", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const report = await reports(c.env.DB);
  return json(200, rq1JSON(report.rq1));
});
app.get("/api/v1/exports/rq2.json", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const report = await reports(c.env.DB);
  return json(200, rq2JSON(report.rq2));
});
app.get("/api/v1/exports/rq3.json", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const report = await reports(c.env.DB);
  return json(200, rq3JSON(report.rq3));
});
app.get("/api/v1/exports/rq4.json", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const report = await reports(c.env.DB);
  return json(200, rq4JSON(report.rq4));
});
app.get("/api/v1/ground-truth", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const rows = await listGroundTruth(c.env.DB);
  return json(200, rows.map(groundTruthJSON));
});
app.post("/api/v1/ground-truth", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const body = await readJSON(c.req.raw);
  if (!body.ok) {
    return json(400, { error: "invalid JSON" });
  }
  const parsed = parseGroundTruth(body.value);
  if (!parsed.ok) {
    return json(parsed.status, { error: parsed.error });
  }
  try {
    await addGroundTruth(c.env.DB, parsed.row);
  } catch {
    return json(400, { error: "could not save ground truth" });
  }
  return json(201, { status: "stored" });
});
app.post("/api/v1/ground-truth/import", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  const text2 = await readText(c.req.raw);
  if (!text2.ok) {
    return json(400, { error: "invalid CSV" });
  }
  const rows = parseCSV(text2.value);
  if (!rows) {
    return json(400, { error: "invalid CSV" });
  }
  let saved = 0;
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    if (i === 0 && row.length > 0 && row[0] === "device_id") {
      continue;
    }
    if (row.length < 6) {
      continue;
    }
    const observed = parseRFC3339(row[4]);
    if (!observed) {
      return json(400, { error: "observed_at must be RFC3339" });
    }
    try {
      await addGroundTruth(c.env.DB, {
        device_id: row[0],
        match_key: row[1],
        reference_type: row[2],
        reference_value: row[3],
        observed_at: formatRFC3339(observed),
        observer: row[5],
        notes: row.length > 6 ? row[6] : ""
      });
    } catch {
      return json(400, { error: "could not import a row" });
    }
    saved++;
  }
  return json(201, { imported: saved });
});
app.post("/api/v1/admin/users", async (c) => {
  const user = await requireAdmin(c);
  if (user instanceof Response) {
    return user;
  }
  const body = await readJSON(c.req.raw);
  if (!body.ok) {
    return json(400, { error: "invalid JSON" });
  }
  const password = typeof body.value.password === "string" ? body.value.password : "";
  const username = typeof body.value.username === "string" ? body.value.username : "";
  const role = typeof body.value.role === "string" ? body.value.role : "";
  if (password.length < 8) {
    return json(400, { error: "password must be at least 8 characters" });
  }
  try {
    await createUser(c.env.DB, username.trim(), password, role);
  } catch {
    return json(400, { error: "could not create user" });
  }
  return json(201, { username, role });
});
app.post("/api/v1/admin/devices", async (c) => {
  const user = await requireAdmin(c);
  if (user instanceof Response) {
    return user;
  }
  const body = await readJSON(c.req.raw);
  if (!body.ok) {
    return json(400, { error: "invalid JSON" });
  }
  const deviceID = typeof body.value.device_id === "string" ? body.value.device_id : "";
  const name = typeof body.value.name === "string" ? body.value.name : "";
  try {
    await upsertDevice(c.env.DB, deviceID.trim(), name.trim());
  } catch {
    return json(400, { error: "could not save device" });
  }
  return json(201, { device_id: deviceID, name });
});
app.post("/api/v1/admin/devices/:device_id/tokens", async (c) => {
  const user = await requireAdmin(c);
  if (user instanceof Response) {
    return user;
  }
  const token2 = await issueDeviceToken(c.env.DB, c.req.param("device_id"));
  if (!token2) {
    return json(404, { error: "device not found" });
  }
  return json(201, { token: token2, note: TOKEN_NOTE });
});
app.post("/api/v1/admin/devices/:device_id/pairing-codes", async (c) => {
  const user = await requireAdmin(c);
  if (user instanceof Response) {
    return user;
  }
  const deviceID = c.req.param("device_id");
  try {
    const issued = await issuePairingCode(c.env.DB, deviceID);
    if (!issued) {
      return json(404, { error: "device not found" });
    }
    return json(201, { code: issued.code, device_id: deviceID, expires_at: issued.expires_at, ttl_seconds: 600 });
  } catch (err) {
    console.log(JSON.stringify({ level: "error", msg: "pairing code failed", err: String(err) }));
    return json(500, { error: "pairing code failed" });
  }
});
app.notFound(() => text("404 page not found\n", 404));
app.onError((err) => {
  console.log(JSON.stringify({ level: "error", msg: "unhandled", err: err.message }));
  return json(500, { error: "internal error" });
});
var http_default = app;
function json(status, value) {
  return new Response(jsonBody(value), {
    status,
    headers: { ...CORS, "Content-Type": "application/json; charset=utf-8" }
  });
}
__name(json, "json");
function text(body, status, extra) {
  return new Response(body, {
    status,
    headers: { ...CORS, "Content-Type": "text/plain; charset=utf-8", ...extra }
  });
}
__name(text, "text");
function attachment(body, contentType, filename) {
  return new Response(body, {
    status: 200,
    headers: {
      ...CORS,
      "Content-Type": contentType,
      "Content-Disposition": `attachment; filename="${filename}"`
    }
  });
}
__name(attachment, "attachment");
function bearer(request) {
  const value = request.headers.get("Authorization") ?? "";
  const prefix = "Bearer ";
  if (!value.startsWith(prefix)) {
    return "";
  }
  return value.slice(prefix.length).trim();
}
__name(bearer, "bearer");
async function readText(request) {
  const declared = request.headers.get("content-length");
  if (declared && Number(declared) > MAX_BODY) {
    return { ok: false };
  }
  const textBody = await request.text();
  if (textBody.length > MAX_BODY) {
    return { ok: false };
  }
  return { ok: true, value: textBody };
}
__name(readText, "readText");
async function readJSON(request) {
  const textBody = await readText(request);
  if (!textBody.ok) {
    return { ok: false };
  }
  if (textBody.value.trim() === "") {
    return { ok: true, value: {} };
  }
  try {
    const parsed = JSON.parse(textBody.value);
    if (parsed === null) {
      return { ok: true, value: {} };
    }
    if (typeof parsed !== "object" || Array.isArray(parsed)) {
      return { ok: false };
    }
    return { ok: true, value: parsed };
  } catch {
    return { ok: false };
  }
}
__name(readJSON, "readJSON");
async function userIfAny(c) {
  const token2 = bearer(c.req.raw);
  if (!token2) {
    return null;
  }
  const user = await userByToken(c.env.DB, token2);
  return user ? { role: user.role } : null;
}
__name(userIfAny, "userIfAny");
async function requireUser(c) {
  const user = await userIfAny(c);
  if (!user) {
    return json(401, { error: "login required" });
  }
  return user;
}
__name(requireUser, "requireUser");
async function requireAdmin(c) {
  const user = await requireUser(c);
  if (user instanceof Response) {
    return user;
  }
  if (user.role !== "admin") {
    return json(403, { error: "admin required" });
  }
  return user;
}
__name(requireAdmin, "requireAdmin");
async function devicePrincipal(c) {
  const token2 = bearer(c.req.raw);
  if (!token2) {
    return json(401, { error: "device token required" });
  }
  const deviceID = await deviceByToken(c.env.DB, token2);
  if (!deviceID) {
    return json(401, { error: "device token rejected" });
  }
  return deviceID;
}
__name(devicePrincipal, "devicePrincipal");
function staleAfter(env) {
  if (!env.STALE_AFTER) {
    return DEFAULT_STALE_MS;
  }
  return parseDuration(env.STALE_AFTER) ?? DEFAULT_STALE_MS;
}
__name(staleAfter, "staleAfter");
function optionalString(value) {
  if (value === void 0 || value === null) {
    return "";
  }
  return typeof value === "string" ? value : null;
}
__name(optionalString, "optionalString");
function parseEvent(raw2) {
  if (!raw2 || typeof raw2 !== "object" || Array.isArray(raw2)) {
    return { ok: false, error: "invalid JSON" };
  }
  const source = raw2;
  const eventID = optionalString(source.event_id);
  const deviceID = optionalString(source.device_id);
  const sessionID = optionalString(source.session_id);
  const sensorAddress = optionalString(source.sensor_address);
  const sensorKind = optionalString(source.sensor_kind);
  const sensorModel = optionalString(source.sensor_model);
  const measurementType = optionalString(source.measurement_type);
  const unit = optionalString(source.unit);
  const clockState = optionalString(source.clock_state);
  const operatingState = optionalString(source.operating_state);
  const schemaVersion = optionalString(source.schema_version);
  if (eventID === null || deviceID === null || sessionID === null || sensorAddress === null || sensorKind === null || sensorModel === null || measurementType === null || unit === null || clockState === null || operatingState === null || schemaVersion === null) {
    return { ok: false, error: "invalid JSON" };
  }
  let monotonic = 0;
  if (source.monotonic_us !== void 0 && source.monotonic_us !== null) {
    if (typeof source.monotonic_us !== "number" || !Number.isInteger(source.monotonic_us)) {
      return { ok: false, error: "invalid JSON" };
    }
    monotonic = source.monotonic_us;
  }
  let wall = null;
  if (source.wall_time_utc !== void 0 && source.wall_time_utc !== null) {
    if (typeof source.wall_time_utc !== "string") {
      return { ok: false, error: "invalid JSON" };
    }
    wall = source.wall_time_utc;
  }
  let values = {};
  if (source.values !== void 0 && source.values !== null) {
    if (typeof source.values !== "object" || Array.isArray(source.values)) {
      return { ok: false, error: "invalid JSON" };
    }
    values = source.values;
  }
  return {
    ok: true,
    event: {
      schema_version: schemaVersion,
      event_id: eventID,
      device_id: deviceID,
      session_id: sessionID,
      sensor_address: sensorAddress,
      sensor_kind: sensorKind,
      sensor_model: sensorModel,
      measurement_type: measurementType,
      unit,
      monotonic_us: monotonic,
      wall_time_utc: wall,
      clock_state: clockState,
      operating_state: operatingState,
      values
    }
  };
}
__name(parseEvent, "parseEvent");
function parseGroundTruth(body) {
  const deviceID = optionalString(body.device_id);
  const matchKey = optionalString(body.match_key);
  const referenceType = optionalString(body.reference_type);
  const referenceValue = optionalString(body.reference_value);
  const observer = optionalString(body.observer);
  const notes = optionalString(body.notes);
  if (deviceID === null || matchKey === null || referenceType === null || referenceValue === null || observer === null || notes === null) {
    return { ok: false, status: 400, error: "invalid JSON" };
  }
  let observed = formatRFC3339(/* @__PURE__ */ new Date());
  if (body.observed_at !== void 0 && body.observed_at !== null && body.observed_at !== "") {
    if (typeof body.observed_at !== "string") {
      return { ok: false, status: 400, error: "invalid JSON" };
    }
    if (body.observed_at !== "0001-01-01T00:00:00Z") {
      const parsed = parseRFC3339(body.observed_at);
      if (!parsed) {
        return { ok: false, status: 400, error: "invalid JSON" };
      }
      observed = formatRFC3339(parsed);
    }
  }
  if (deviceID === "" || matchKey === "" || referenceType === "" || observer === "") {
    return { ok: false, status: 400, error: "device_id, match_key, reference_type, and observer are required" };
  }
  return {
    ok: true,
    row: {
      device_id: deviceID,
      match_key: matchKey,
      reference_type: referenceType,
      reference_value: referenceValue,
      observed_at: observed,
      observer,
      notes
    }
  };
}
__name(parseGroundTruth, "parseGroundTruth");
function parseCSV(text2) {
  const rows = [];
  let row = [];
  let field = "";
  let quoted = false;
  for (let i = 0; i < text2.length; i++) {
    const ch = text2[i];
    if (quoted) {
      if (ch === '"') {
        if (text2[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          quoted = false;
        }
      } else {
        field += ch;
      }
      continue;
    }
    if (ch === '"') {
      quoted = true;
      continue;
    }
    if (ch === ",") {
      row.push(field);
      field = "";
      continue;
    }
    if (ch === "\n" || ch === "\r") {
      if (ch === "\r" && text2[i + 1] === "\n") {
        i++;
      }
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
      continue;
    }
    field += ch;
  }
  if (quoted) {
    return null;
  }
  if (field.length > 0 || row.length > 0) {
    row.push(field);
    rows.push(row);
  }
  return rows;
}
__name(parseCSV, "parseCSV");
function storedEventJSON(row) {
  const event = JSON.parse(row.canonical_json);
  return new Ordered([
    ["event", eventStruct(event)],
    ["payload_hash", row.payload_hash],
    ["canonical_json", row.canonical_json],
    ["server_received_at", row.server_received_at]
  ]);
}
__name(storedEventJSON, "storedEventJSON");
function eventStruct(event) {
  return new Ordered([
    ["schema_version", event.schema_version],
    ["event_id", event.event_id],
    ["device_id", event.device_id],
    ["session_id", event.session_id],
    ["sensor_address", event.sensor_address],
    ["sensor_kind", event.sensor_kind],
    ["sensor_model", event.sensor_model],
    ["measurement_type", event.measurement_type],
    ["unit", event.unit],
    ["monotonic_us", event.monotonic_us],
    ["wall_time_utc", event.wall_time_utc],
    ["clock_state", event.clock_state],
    ["operating_state", event.operating_state],
    ["values", event.values]
  ]);
}
__name(eventStruct, "eventStruct");
function rateJSON(rate) {
  const entries = [
    ["status", rate.status],
    ["value", rate.value],
    ["numerator", rate.numerator],
    ["denominator", rate.denominator]
  ];
  if (rate.reason) {
    entries.push(["reason", rate.reason]);
  }
  return new Ordered(entries);
}
__name(rateJSON, "rateJSON");
function rq1JSON(report) {
  return new Ordered([
    ["note", report.note],
    ["device_journal", report.device_journal],
    ["observer", report.observer],
    ["ack_rate", rateJSON(report.ack_rate)],
    ["miss_rate", rateJSON(report.miss_rate)],
    ["delivery_rate", rateJSON(report.delivery_rate)]
  ]);
}
__name(rq1JSON, "rq1JSON");
function rq2JSON(report) {
  return new Ordered([
    ["note", report.note],
    ["confusion", report.confusion],
    ["unmatched_ground_truth", report.unmatched_ground_truth],
    ["recall", rateJSON(report.recall)],
    ["specificity", rateJSON(report.specificity)]
  ]);
}
__name(rq2JSON, "rq2JSON");
function rq3JSON(report) {
  return new Ordered([
    ["note", report.note],
    ["stored_events", report.stored_events],
    ["duplicate_acks", report.duplicate_acks],
    ["conflicts", report.conflicts],
    ["duplicate_attempt_rate", rateJSON(report.duplicate_attempt_rate)],
    ["pending_on_server", report.pending_on_server]
  ]);
}
__name(rq3JSON, "rq3JSON");
function susJSON(item) {
  const entries = [
    ["device_id", item.device_id],
    ["match_key", item.match_key],
    ["score", item.score],
    ["status", item.status]
  ];
  if (item.reason) {
    entries.push(["reason", item.reason]);
  }
  return new Ordered(entries);
}
__name(susJSON, "susJSON");
function rq4JSON(report) {
  return new Ordered([
    ["note", report.note],
    ["task_dispositions", report.task_dispositions],
    ["sus", report.sus.map(susJSON)]
  ]);
}
__name(rq4JSON, "rq4JSON");
async function reports(db) {
  const found = await evidence(db);
  const tally = await counts(db);
  return {
    rq1: summarizeRQ1(found.events, found.ledger),
    rq2: summarizeRQ2(found.events, found.ledger),
    rq3: summarizeRQ3(tally.stored, tally.duplicates, tally.conflicts),
    rq4: summarizeRQ4(found.events)
  };
}
__name(reports, "reports");

// src/index.ts
var index_default = {
  fetch(request, env, ctx) {
    return Promise.resolve(http_default.fetch(request, env, ctx));
  }
};
export {
  index_default as default
};
//# sourceMappingURL=index.js.map
