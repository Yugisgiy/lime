package lime._internal.backend.html5;

import haxe.io.Bytes;
import js.html.AnchorElement;
import js.html.Blob;
import js.html.ErrorEvent;
import js.html.Event;
import js.html.Image as JSImage;
import js.html.ProgressEvent;
import js.html.URL;
import js.html.XMLHttpRequest;
import js.html.XMLHttpRequestResponseType;
import js.Browser;
import lime._internal.format.Base64;
import lime.app.Future;
import lime.app.Promise;
import lime.graphics.Image;
import lime.graphics.ImageBuffer;
import lime.net.HTTPRequest;
import lime.net.HTTPRequestHeader;
import lime.utils.AssetType;

@:access(lime.graphics.ImageBuffer)
@:access(lime.graphics.Image)
class HTML5HTTPRequest
{
	private static inline var OPTION_REVOKE_URL:Int = 1 << 0;

	private static var activeRequests = 0;
	private static var originElement:AnchorElement;
	private static var originHostname:String;
	private static var originPort:String;
	private static var originProtocol:String;
	private static var requestLimit = 17;
	private static var requestQueue = new List<QueueItem>();
	private static var supportsImageProgress:Null<Bool>;

	private var binary:Bool;
	private var parent:_IHTTPRequest;
	private var request:XMLHttpRequest;
	private var validStatus0:Bool;

	public function new()
	{
		validStatus0 = #if allow_status_0 true #else ~/Tizen/gi.match(Browser.window.navigator.userAgent) #end;
	}

	public function cancel():Void
	{
		if (request != null)
		{
			request.abort();
		}
	}

	public function init(parent:_IHTTPRequest):Void
	{
		this.parent = parent;
	}

	private function load(uri:String, progress:Dynamic, readyStateChange:Dynamic):Void
	{
		request = new XMLHttpRequest();

		if (parent.method == POST)
		{
			request.upload.addEventListener("progress", progress, false);
		}
		else
		{
			request.addEventListener("progress", progress, false);
		}

		request.onreadystatechange = readyStateChange;

		var query = "";

		if (parent.data == null)
		{
			for (key in parent.formData.keys())
			{
				if (query.length > 0) query += "&";
				var value:Dynamic = parent.formData.get(key);
				if (key.indexOf("[]") > -1 && (value is Array))
				{
					var arrayValue:String = Lambda.map(value, function(v:String)
					{
						return StringTools.urlEncode(v);
					}).join('&amp;${key}=');
					query += StringTools.urlEncode(key) + "=" + arrayValue;
				}
				else
				{
					query += StringTools.urlEncode(key) + "=" + StringTools.urlEncode(Std.string(value));
				}
			}

			if (parent.method == GET && query != "")
			{
				if (uri.indexOf("?") > -1)
				{
					uri += "&" + query;
				}
				else
				{
					uri += "?" + query;
				}

				query = "";
			}
		}

		request.open(Std.string(parent.method), uri, true);

		if (parent.timeout > 0)
		{
			request.timeout = parent.timeout;
		}

		if (binary)
		{
			request.responseType = ARRAYBUFFER;
		}

		var contentType = null;

		for (header in parent.headers)
		{
			if (header.name == "Content-Type")
			{
				contentType = header.value;
			}
			else
			{
				request.setRequestHeader(header.name, header.value);
			}
		}

		if (parent.contentType != null)
		{
			contentType = parent.contentType;
		}

		if (contentType == null)
		{
			if (parent.data != null)
			{
				contentType = "application/octet-stream";
			}
			else if (query != "")
			{
				contentType = "application/x-www-form-urlencoded";
			}
		}

		if (contentType != null)
		{
			request.setRequestHeader("Content-Type", contentType);
		}

		if (parent.withCredentials)
		{
			request.withCredentials = true;
		}

		if (parent.data != null)
		{
			request.send(parent.data.getData());
		}
		else
		{
			request.send(query);
		}
	}

	public function loadData(uri:String):Future<Bytes>
	{
		var promise = new Promise<Bytes>();

		if (activeRequests < requestLimit)
		{
			activeRequests++;
			__loadData(uri, promise);
		}
		else
		{
			requestQueue.add(
				{
					instance: this,
					uri: uri,
					promise: promise,
					type: AssetType.BINARY,
					options: 0
				});
		}

		return promise.future;
	}

	private static function loadImage(uri:String):Future<Image>
	{
		var promise = new Promise<Image>();

		if (activeRequests < requestLimit)
		{
			activeRequests++;
			__loadImage(uri, promise, 0);
		}
		else
		{
			requestQueue.add(
				{
					instance: null,
					uri: uri,
					promise: promise,
					type: AssetType.IMAGE,
					options: 0
				});
		}

		return promise.future;
	}

	private static function loadImageFromBytes(bytes:Bytes, type:String):Future<Image>
	{
		var uri = __createBlobURIFromBytes(bytes, type);
		if (uri != null)
		{
			var promise = new Promise<Image>();

			if (activeRequests < requestLimit)
			{
				activeRequests++;
				__loadImage(uri, promise, OPTION_REVOKE_URL);
			}
			else
			{
				requestQueue.add(
					{
						instance: null,
						uri: uri,
						promise: promise,
						type: AssetType.IMAGE,
						options: OPTION_REVOKE_URL
					});
			}

			return promise.future;
		}
		else
		{
			return loadImage("data:" + type + ";base64," + Base64.encode(bytes));
		}
	}

	public function loadText(uri:String):Future<String>
	{
		var promise = new Promise<String>();

		if (activeRequests < requestLimit)
		{
			activeRequests++;
			__loadText(uri, promise);
		}
		else
		{
			requestQueue.add(
				{
					instance: this,
					uri: uri,
					promise: promise,
					type: AssetType.TEXT,
					options: 0
				});
		}

		return promise.future;
	}

	private static function processQueue():Void
	{
		if (activeRequests < requestLimit && requestQueue.length > 0)
		{
			activeRequests++;

			var queueItem = requestQueue.pop();

			switch (queueItem.type)
			{
				case IMAGE:
					__loadImage(queueItem.uri, queueItem.promise, queueItem.options);

				case TEXT:
					queueItem.instance.__loadText(queueItem.uri, queueItem.promise);

				case BINARY:
					queueItem.instance.__loadData(queueItem.uri, queueItem.promise);

				default:
					activeRequests--;
			}
		}
	}

	private function processResponse():Void
	{
		if (parent.enableResponseHeaders)
		{
			parent.responseHeaders = [];
			var name, value;

			for (line in request.getAllResponseHeaders().split("\n"))
			{
				name = StringTools.trim(line.substr(0, line.indexOf(":")));
				value = StringTools.trim(line.substr(line.indexOf(":") + 1));

				if (name != "")
				{
					parent.responseHeaders.push(new HTTPRequestHeader(name, value));
				}
			}
		}

		parent.responseStatus = request.status;
	}

	private static inline function __createBlobURIFromBytes(bytes:Bytes, type:String):String
	{
		return URL.createObjectURL(new Blob([bytes.getData()], {type: type}));
	}

	private static function __fixHostname(hostname:String):String
	{
		return hostname == null ? "" : hostname;
	}

	private static function __fixPort(port:String, protocol:String):String
	{
		if (port == null || port == "")
		{
			return switch (protocol)
			{
				case "ftp:": "21";
				case "gopher:": "70";
				case "http:": "80";
				case "https:": "443";
				case "ws:": "80";
				case "wss:": "443";
				default: "";
			}
		}

		return port;
	}

	private static function __fixProtocol(protocol:String):String
	{
		return (protocol == null || protocol == "") ? "http:" : protocol;
	}

	private static function __isInMemoryURI(uri:String):Bool
	{
		return StringTools.startsWith(uri, "data:") || StringTools.startsWith(uri, "blob:");
	}

	private static function __isSameOrigin(path:String):Bool
	{
		if (path == null || path == "") return true;
		if (__isInMemoryURI(path)) return true;

		if (originElement == null)
		{
			originElement = Browser.document.createAnchorElement();

			originHostname = __fixHostname(Browser.location.hostname);
			originProtocol = __fixProtocol(Browser.location.protocol);
			originPort = __fixPort(Browser.location.port, originProtocol);
		}

		var a = originElement;
		a.href = path;

		if (a.hostname == "")
		{
			// Workaround for IE, updates other properties
			a.href = a.href;
		}

		var hostname = __fixHostname(a.hostname);
		var protocol = __fixProtocol(a.protocol);
		var port = __fixPort(a.port, protocol);

		var sameHost = (hostname == "" || (hostname == originHostname));
		var samePort = (port == "" || (port == originPort));

		return (protocol != "file:" && sameHost && samePort);
	}

	public function __loadData(uri:String, promise:Promise<Bytes>):Void
	{
		var progress = function(event)
		{
			promise.progress(event.loaded, event.total);
		}

		var readyStateChange = function(event)
		{
			if (request.readyState != 4) return;

			var bytes = null;
			if (request.responseType == NONE)
			{
				if (request.responseText != null)
				{
					bytes = Bytes.ofString(request.responseText);
				}
			}
			else if (request.response != null)
			{
				bytes = Bytes.ofData(request.response);
			}

			if (request.status != null && ((request.status >= 200 && request.status < 400) || (validStatus0 && request.status == 0)))
			{
				processResponse();
				promise.complete(bytes);
			}
			else
			{
				processResponse();
				promise.error(new _HTTPRequestErrorResponse(request.status, bytes));
			}

			request = null;

			activeRequests--;
			processQueue();
		}

		binary = true;
		load(uri, progress, readyStateChange);
	}

	private static function __loadImage(uri:String, promise:Promise<Image>, options:Int):Void
	{
		var image:JSImage = untyped js.Syntax.code('new window.Image ()');

		if (!__isSameOrigin(uri))
		{
			image.crossOrigin = "Anonymous";
		}

		if (supportsImageProgress == null)
		{
			supportsImageProgress = untyped js.Syntax.code("'onprogress' in image");
		}

		if (supportsImageProgress || __isInMemoryURI(uri))
		{
			image.addEventListener("load", function(event)
			{
				__revokeBlobURI(uri, options);
				var buffer = new ImageBuffer(null, image.width, image.height);
				buffer.__srcImage = cast image;

				activeRequests--;
				processQueue();

				promise.complete(new Image(buffer));
			}, false);

			image.addEventListener("progress", function(event)
			{
				promise.progress(event.loaded, event.total);
			}, false);

			image.addEventListener("error", function(event)
			{
				__revokeBlobURI(uri, options);

				activeRequests--;
				processQueue();

				promise.error(new _HTTPRequestErrorResponse(event.detail, null));
			}, false);

			image.src = uri;
		}
		else
		{
			var request = new XMLHttpRequest();

			request.onload = function(_)
			{
				activeRequests--;
				processQueue();

				var img = new Image();
				img.__fromBytes(Bytes.ofData(request.response), function(img)
				{
					promise.complete(img);
				});
			}

			request.onerror = function(event:ErrorEvent)
			{
				promise.error(new _HTTPRequestErrorResponse(event.message, null));
			}

			request.onprogress = function(event:ProgressEvent)
			{
				if (event.lengthComputable)
				{
					promise.progress(event.loaded, event.total);
				}
			}

			request.open("GET", uri, true);
			request.responseType = XMLHttpRequestResponseType.ARRAYBUFFER;
			request.overrideMimeType('text/plain; charset=x-user-defined');
			request.send(null);
		}
	}

	private function __loadText(uri:String, promise:Promise<String>):Void
	{
		var progress = function(event)
		{
			promise.progress(event.loaded, event.total);
		}

		var readyStateChange = function(event)
		{
			if (request.readyState != 4) return;

			if (request.status != null && ((request.status >= 200 && request.status < 400) || (validStatus0 && request.status == 0)))
			{
				processResponse();
				promise.complete(request.responseText);
			}
			else
			{
				processResponse();
				promise.error(new _HTTPRequestErrorResponse(request.status, request.responseText));
			}

			request = null;

			activeRequests--;
			processQueue();
		}

		binary = false;
		load(uri, progress, readyStateChange);
	}

	private static function __revokeBlobURI(uri:String, options:Int):Void
	{
		if ((options & OPTION_REVOKE_URL) != 0)
		{
			URL.revokeObjectURL(uri);
		}
	}
}

@:dox(hide) typedef QueueItem =
{
	var instance:HTML5HTTPRequest;
	var type:AssetType;
	var promise:Dynamic;
	var uri:String;
	var options:Int;
}
