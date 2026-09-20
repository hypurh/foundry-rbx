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
		* Circular dependencies through Loader:Get() are automatically detected.

	dependencies:
		* evaera/promise@4.0.0 -> ../Packages/Promise
	
	docs:
		* https://wally.run/package/hypurh/foundry
]]


---- DEPENDENCIES ----
local Promise = require("../Packages/Promise")


---- CORE MODULES ----
local Types = require("@self/Types")
-- local Config = require("@self/Config")


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

-- If neccessary, yields till the loader has loaded.
function loader.YieldTillLoaded(self: LoaderObject)
	if not self._loaded then self.Loaded:await() end
end

-- Returns the record module, yielding until it finishes loading if necessary.
function loader.Get(self: LoaderObject, name: string)
	assert(self._initialized, `Loader for Folder "{self.Folder:GetFullName()}" has not been initialized!`)

	local dependency = self._cache[name]
	if not dependency then
		warn(`Module: {name} not recorded - May not exist or be disabled.`)
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

		assert(not hasPath(dependency), `Circular dependency detected involving module: "{name}"!`)
	end

	local success, result = dependency.promise:await()
	if not success then
		error(`Failed to load module "{name}" for Folder "{self.Folder:GetFullName()}": {result}`, 2)
	end

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

	local selectedModuleScripts = {}
	for _, moduleScript in self.Folder:GetChildren() do
		if not moduleScript:IsA("ModuleScript") then continue end
		if not moduleScript:GetAttribute("Enabled") then
			warn(`Skipping {moduleScript:GetFullName()} as it's not Enabled.`)
			continue
		end

		local name = moduleScript.Name
		assert(not selectedModuleScripts[name], `Duplicate module "{name}" found in Folder "{self.Folder:GetFullName()}"! Module names must be unique.`)

		pendingModules += 1

		selectedModuleScripts[name] = moduleScript

		self._cache[name] = {
			name = name,

			instance = moduleScript,
			module = nil,

			promise = nil,
			_resolve = nil,
			_reject = nil,

			thread = nil,
			dependencies = {},

			_loading = true,
		}
		local record = self._cache[name]

		local promise = Promise.new(function(resolve, reject)
			record._resolve = resolve
			record._reject = reject
		end)

		promise:catch(function() end)
		record.promise = promise
	end

	for name, moduleScript in selectedModuleScripts do
		local record = self._cache[name]
		local resolve = record._resolve
		local reject = record._reject

		task.spawn(function()
			assert(record, `Record for "{name}" missing!`)

			local thread = coroutine.running()
			record.thread = thread
			self._threads[thread] = record

			local function finish(success: boolean, result: any)
				self._threads[thread] = nil
				record._loading = false

				if success then
					record.module = result
					resolve(result)

				else reject(result) end

				pendingModules -= 1
				pendingUpdated()
			end

			local success, result = pcall(function()
				local module = require(moduleScript)
				assert(type(module) == "table", "Module is not a table")
				return module
			end)

			if not success then
				warn(`Failed to require module "{name}":`)
				warn(`	└─ {result}`)
				finish(false, result)
				return
			end

			if result.Init ~= nil then
				assert(type(result.Init) == "function", `Module "{name}" has an Init member that is not a function!`)

				local initSuccess, initErr = pcall(result.Init, result, self, context)

				if not initSuccess then
					warn(`Failed to init module "{name}":`)
					warn(`	└─ {initErr}`)
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