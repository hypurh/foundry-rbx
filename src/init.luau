--[[
	███████╗ ██████╗ ██╗   ██╗███╗   ██╗██████╗ ██████╗ ██╗   ██╗
	██╔════╝██╔═══██╗██║   ██║████╗  ██║██╔══██╗██╔══██╗╚██╗ ██╔╝
	█████╗  ██║   ██║██║   ██║██╔██╗ ██║██║  ██║██████╔╝ ╚████╔╝ 
	██╔══╝  ██║   ██║██║   ██║██║╚██╗██║██║  ██║██╔══██╗  ╚██╔╝  
	██║     ╚██████╔╝╚██████╔╝██║ ╚████║██████╔╝██║  ██║   ██║   
	╚═╝      ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝╚═════╝ ╚═╝  ╚═╝   ╚═╝   
	a package by @nothypurh<roblox> @hypurh<github> | © 2026 (yyyy-mm-dd)
	// licensed under the MIT License

	Foundry is a Roblox module loader for organizing, loading, and resolving
	ModuleScripts within a Folder.

	notes:
		* Modules must have the "Enabled" attribute set to true to be loaded.
		* ModuleScript names must be unique within the managed Folder.

	dependencies:
		* evaera/promise@4.0.0 -> ../Packages/Promise
	
	docs:
		* https://wally.run/package/hypurh/foundry
]]


---- DEPENDENCIES ----
local Promise = require("./promise")


---- CORE MODULES ----
local Types = require("@self/Types")


---- CONSTANTS ----
type Promise = Types.Promise
type LoaderObject = Types.LoaderObject


---- DEFINITION ----
local loader = {}
loader.__index = loader


---- OBJECT METHODS ----

-- Creates a new LoaderObject.
function loader.new(config: {Folder: Folder}): LoaderObject
	assert(type(config) == "table", "Passed config is not a valid table!")

	local folder = config.Folder
	assert(typeof(folder) == "Instance" and folder:IsA("Folder"), `Passed Folder is not a valid Folder!`)

	local self = setmetatable({
		Folder = folder,

		_cache = {},
		_threads = {},

		Loaded = nil,
		_loadedResolve = nil,

		_loaded = false,
		_initialized = false,
	}, loader)
	self.Loaded = Promise.new(function(resolve) self._loadedResolve = resolve end)

	return self
end

-- If necessary, yields till the loader has loaded.
function loader.YieldTillLoaded(self: LoaderObject)
	if not self._loaded then self.Loaded:await() end
end

-- Returns the record module, yielding until it finishes loading if necessary.
-- Returns the record module, yielding until it finishes loading if necessary.
function loader.Get(self: LoaderObject, name: string)
	assert(self._initialized, `Loader for Folder "{self.Folder:GetFullName()}" has not been initialized!`)

	local dependency = self._cache[name]
	if not dependency then
		warn(`Module "{name}" not found or is disabled.`)
		return
	end

	local currentThread = coroutine.running()
	local requester = self._threads[currentThread]

	if requester then
		requester.dependencies[name] = true

		local visited = {}
		local function hasPath(current)
			if current == requester then return true end
			if visited[current] then return false end

			visited[current] = true

			for dependencyName in current.dependencies do
				local nextDependency = self._cache[dependencyName]
				if nextDependency and hasPath(nextDependency) then return true end
			end

			return false
		end

		assert(not hasPath(dependency), `Circular dependency detected: "{requester.name}" -> "{name}"`)
	end

	local success, result = dependency.promise:await()
	if not success then error(result, 2) end

	return result
end

-- Loads all enabled modules in the loader.
function loader.Init(self: LoaderObject, ...)
	assert(not self._initialized, "Loader already initialized! - A loader object may only be initialized once.")
	self._initialized = true

	local context = ...
	local pendingModules = 0

	local function pendingUpdated()
		if pendingModules <= 0 and not self._loaded then
			self._loaded = true
			self._loadedResolve()
		end
	end

	for _, moduleScript in self.Folder:GetChildren() do
		if not moduleScript:IsA("ModuleScript") then continue end
		if not moduleScript:GetAttribute("Enabled") then
			warn(`Skipping {moduleScript:GetFullName()} as it's not Enabled.`)
			continue
		end

		local name = moduleScript.Name
		assert(not self._cache[name], `Duplicate module "{name}" found in Folder "{self.Folder:GetFullName()}"! Module names must be unique.`)

		pendingModules += 1

		local record = {
			name = name,

			instance = moduleScript,
			module = nil,

			promise = nil,
			_resolve = nil,
			_reject = nil,

			dependencies = {},
		}

		local promise = Promise.new(function(_resolve, _reject)
			record._resolve = _resolve
			record._reject = _reject
		end)
		promise:catch(function() end)
		record.promise = promise

		self._cache[name] = record
	end
	for name, record in self._cache do
		task.spawn(function()
			local thread = coroutine.running()
			self._threads[thread] = record

			local function finish(success: boolean, result: any)
				self._threads[thread] = nil

				if success then
					record.module = result
					record._resolve(result)

				else record._reject(result) end

				pendingModules -= 1
				pendingUpdated()
			end

			local success, result = pcall(function()
				local module = require(record.instance)
				assert(type(module) == "table", "Module is not a table")
				return module
			end)

			if not success then
				warn(`Failed to require "{name}": {result}`)
				finish(false, result)
				return
			end

			if result.Init ~= nil then
				assert(type(result.Init) == "function", `Module "{name}" has an Init member that is not a function!`)

				local initSuccess, initErr = pcall(result.Init, result, self, context)

				if not initSuccess then
					warn(`Failed to initialize "{name}": {initErr}`)
					finish(false, initErr)
					return
				end
			end

			finish(true, result)
		end)
	end

	pendingUpdated()

	return self
end


---- RETURN ----
return loader