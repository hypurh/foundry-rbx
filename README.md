# *`foundry`*

> Foundry is a Roblox module loader for organizing modules in a Folder, loading them asynchronously, and resolving module dependencies through `Loader:Get()`.

## Install

Add Foundry to your Roblox project with Wally:

```toml
[dependencies]
Foundry = "hypurh/foundry@0.1.0"
```

Then run:

```bash
wally install
```

Require Foundry from the generated `Packages` folder:

```lua
local Foundry = require(Packages.Foundry)
```

## Basic Usage

Create a Folder containing the modules you want Foundry to manage. Each module must have its `Enabled` attribute set to `true`.

```lua
local Foundry = require(Packages.Foundry)

local modules = script.Parent.Modules

local loader = Foundry.new({
	Folder = modules,
})

loader:Init()
loader:YieldTillLoaded()

local inventory = loader:Get("Inventory")
inventory:Refresh()
```

`Init()` begins loading all enabled ModuleScripts and returns the loader.

`YieldTillLoaded()` yields until every enabled module has finished loading.

`Get()` yields until the requested module finishes loading if it is still in the process of loading.

## Module Format

Foundry modules must return a table. Modules may optionally define an `Init` method, which Foundry calls after requiring the module.

```lua
local Inventory = {}

function Inventory:Init(loader, context)
	self.Data = context.DataStore
	self.Users = loader:Get("Users")
end

function Inventory:Refresh()
	-- Module implementation
end

return Inventory
```

A context can be passed to `Init()` and is provided to every module's `Init` method:

```lua
loader:Init({
	DataStore = dataStore,
})
```

The module's `Init` method receives:

1. `self` — the module itself
2. `loader` — the loader that is initializing the module
3. `context` — the value passed to `loader:Init(...)`

For example:

```lua
function Inventory:Init(loader, context)
	-- self     -> Inventory
	-- loader   -> the current LoaderObject
	-- context  -> the table passed to loader:Init(...)
end
```

## Rules

* ModuleScript names must be unique within the managed Folder.
* Only direct child ModuleScripts with `Enabled` set to `true` are loaded.
* A module's `Init` member must be a function when present.
* Circular dependencies created through `loader:Get()` raise an error.
* A loader can only be initialized once.
* `Get()` returns `nil` when the requested module is not registered.

## API

### `Foundry.new(config: { Folder: Folder }): LoaderObject`

Creates and returns a new loader for `config.Folder`.

The Folder is not loaded until `Init()` is called.

### `loader:Init(...): LoaderObject`

Initializes the loader and begins asynchronously loading all enabled ModuleScripts.

For each loaded module, Foundry calls its optional `Init` method as:

```lua
module:Init(loader, ...)
```

The arguments after `loader` are the same values passed to `loader:Init(...)`.

Returns the loader.

### `loader:Get(name: string): Module?`

Returns the module registered under `name`.

If the module is still loading, `Get()` yields until it finishes.

If the module fails to load, the error is propagated to the caller.

Returns `nil` if no enabled module with the given name is registered.

`Get()` also tracks module dependencies and detects circular dependencies.

### `loader:YieldTillLoaded(): ()`

Yields until all enabled modules have finished loading.

This waits for the loading process to complete, including modules that failed to load.
