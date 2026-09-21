local Promise = require("../Promise")

export type Promise = typeof(Promise.new())

export type Module = {
	Init: (self: Module, loader: LoaderObject, context: any) -> (),
	
	-- _foundry_: {}, -- i might add this in the future for sm stuf

	[any]: any,
}

type LoaderCacheValue = {
	name: string,

	instance: ModuleScript,
	module: Module?,
	
	promise: Promise,
	_resolve: (module: Module) -> (),
	_reject: (err: string) -> (),

	dependencies: {[string]: boolean},
}
type LoaderCache = {[string]: LoaderCacheValue}

export type LoaderObject = {
	Folder: Folder,

	_cache: LoaderCache,
	_threads: {[thread]: LoaderCacheValue},

	Loaded: Promise,
	_loadedResolve: () -> (),

	_loaded: boolean,
	_initialized: boolean,

	YieldTillLoaded: (self: LoaderObject) -> (),
	Get: (self: LoaderObject, name: string) -> Module?,

	Init: (self: LoaderObject, context: any) -> LoaderObject,
}

return {}