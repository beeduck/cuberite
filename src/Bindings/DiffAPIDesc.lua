-- DiffAPIDesc.lua

-- Creates a diff file containing documentation that is available from ToLua++'s doxycomment parsing, but not yet included in APIDesc.lua

require("lfs")





--- Translation for function names whose representation in APIDesc is different from the one in Docs
-- Dictionary of "DocsName" -> "DescName"
local g_FunctionNameDocsToDesc =
{
	["new"]    = "constructor",
	["delete"] = "destructor",
	[".add"]   = "operator_plus",
	[".div"]   = "operator_div",
	[".eq"]    = "operator_eq",
	[".mul"]   = "operator_mul",
	[".sub"]   = "operator_sub",
}





--- Translation from C types to Lua types
-- Dictionary of "CType" -> "LuaType"
local g_CTypeToLuaType =
{
	AString = "string",
	bool = "boolean",
	Byte = "number",
	char = "number",
	double = "number",
	float = "number",
	ForEachChunkProvider = "cWorld",
	int = "number",
	size_t = "number",
	unsigned = "number",
	["const AString"] = "string",
	["const char*"] = "string",
	["Vector3<int>"]    = "Vector3i",
	["Vector3<float>"]  = "Vector3f",
	["Vector3<double>"] = "Vector3d",
}





--- Functions that should be ignored
-- Dictionary of "FunctionName" -> true for each ignored function
local g_IgnoreFunction =
{
	destructor = true,
}





local function caseInsensitiveCompare(a_Text1, a_Text2)
	return (a_Text1:lower() < a_Text2:lower())
end





--- Loads the APIDesc.lua and its child files, returns the complete description
-- Returns a table with Classes and Hooks members, Classes being a dictionary of "ClassName" -> { desc }
local function loadAPIDesc()
	-- Load the main APIDesc.lua file:
	local apiDescPath = "../../Server/Plugins/APIDump/"
	local desc = dofile(apiDescPath .. "APIDesc.lua")
	if not(desc) then
		error("Failed to load APIDesc")
	end
	
	-- Merge in the information from all files in the Classes subfolder:
	local classesPath = apiDescPath .. "Classes/"
	for fnam in lfs.dir(apiDescPath .. "Classes") do
		if (string.find(fnam, ".*%.lua$")) then
			local tbls = dofile(classesPath .. fnam)
			for k, cls in pairs(tbls) do
				desc.Classes[k] = cls;
			end
		end
	end
	return desc
end





--- Loads the API documentation generated by ToLua++'s parser
-- Returns a dictionary of "ClassName" -> { docs }
local function loadAPIDocs()
	-- Get the filelist:
	local files = dofile("docs/_files.lua")
	if not(files) then
		error("Failed to load _files.lua from docs")
	end
	
	-- Load the docs from all files, merge into a single dictionary:
	local res = {}
	for _, fnam in ipairs(files) do
		local docs = dofile("docs/" .. fnam)
		if (docs) then
			for k, v in pairs(docs) do
				assert(not(res[k]))  -- Do we have a duplicate documentation entry?
				res[k] = v
			end
		end
	end
	return res
end





--- Returns whether the function signature in the description matches the function documentation
-- a_FunctionDesc is a single description for a function, as loaded from APIDesc.lua (one <FnDesc> item)
-- a_FunctionDoc is a single documentation item for a function, as loaded from ToLua++'s parser
local function functionDescMatchesDocs(a_FunctionDesc, a_FunctionDoc)
	-- Check the number of parameters:
	local numParams
	if (not(a_FunctionDesc.Params) or (a_FunctionDesc.Params == "")) then
		numParams = 0
	else
		_, numParams = string.gsub(a_FunctionDesc.Params, ",", "")
		numParams = numParams + 1
	end
	if (#(a_FunctionDoc.Params) ~= numParams) then
		return false
	end
	
	return true
end





--- Returns an array of function descriptions that are in a_FunctionDocs but are missing from a_FunctionDescs
-- a_FunctionDescs is an array of function descriptions, as loaded from APIDesc.lua (normalized into array)
-- a_FunctionDocs is an array of function documentation items, as loaded from ToLua++'s parser
-- If all descriptions match, nil is returned instead
local function listMissingClassSingleFunctionDescs(a_FunctionDescs, a_FunctionDocs)
	-- Generate a helper map of index -> true that monitors a_FunctionDescs' items' usage:
	local freeDescs = {}
	for i = 1, #a_FunctionDescs do
		freeDescs[i] = true
	end
	
	-- For each documentation item, try to find a match in a_FunctionDescs that hasn't been used yet:
	local res = {}
	for _, docs in ipairs(a_FunctionDocs) do
		local hasFound = false
		for idx, _ in pairs(freeDescs) do
			local desc = a_FunctionDescs[idx]
			if (functionDescMatchesDocs(desc, docs)) then
				freeDescs[idx] = nil
				hasFound = true
				break
			end
		end  -- for idx - freeDescs[]
		if not(hasFound) then
			table.insert(res, docs)
		end
	end  -- for docs - a_FunctionDocs[]
	
	-- If no result, return nil instead of an empty table:
	if not(res[1]) then
		return nil
	end
	return res
end





--- Returns a dict of "FnName" -> { { <FnDesc> }, ... } that are documented in a_FunctionDocs but missing from a_FunctionDescs
-- If there are no such descriptions, returns nil instead
-- a_FunctionDescs is a dict of "FnName" -> { <FnDescs> } loaded from APIDesc.lua et al
--    <FnDescs> may be a single desc or an array of those
-- a_FunctionDocs is a dict og "FnName" -> { { <FnDesc> }, ... } loaded from ToLua++'s parser
local function listMissingClassFunctionDescs(a_FunctionDescs, a_FunctionDocs)
	-- Match the docs and descriptions for each separate function:
	local res = {}
	local hasSome = false
	a_FunctionDescs = a_FunctionDescs or {}
	a_FunctionDocs = a_FunctionDocs or {}
	for fnName, fnDocs in pairs(a_FunctionDocs) do
		local fnDescName = g_FunctionNameDocsToDesc[fnName] or fnName
		if not(g_IgnoreFunction[fnDescName]) then
			local fnDescs = a_FunctionDescs[fnDescName]
			if not(fnDescs) then
				-- Function not described at all, insert a dummy empty description for the matching:
				fnDescs = {}
			elseif not(fnDescs[1]) then
				-- Function has a single description, convert it to the same format as multi-overload functions use:
				fnDescs = { fnDescs }
			end
			local missingDocs = listMissingClassSingleFunctionDescs(fnDescs, fnDocs)
			if (missingDocs) then
				res[fnName] = missingDocs
				hasSome = true
			end
		end  -- not ignored
	end  -- for fnName, fnDocs - a_FunctionDocs[]
	if not(hasSome) then
		return nil
	end
	return res
end





--- Returns a dictionary of "SymbolName" -> { <desc> } for any variable or constant that is documented but not described
-- a_VarConstDescs is an array of variable or constant descriptions, as loaded from APIDesc.lua
-- a_VarConstDocs is an array of variable or constant documentation items, as loaded from ToLua++'s parser
-- If no symbol is to be returned, returns nil instead
local function listMissingClassVarConstDescs(a_VarConstDescs, a_VarConstDocs)
	-- Match the docs and descriptions for each separate function:
	local res = {}
	local hasSome = false
	a_VarConstDescs = a_VarConstDescs or {}
	a_VarConstDocs = a_VarConstDocs or {}
	for symName, symDocs in pairs(a_VarConstDocs) do
		local symDesc = a_VarConstDescs[symName]
		if (
			not(symDesc) or        -- Symbol not described at all
			not(symDesc.Notes) or  -- Non-existent description
			(
				(symDesc.Notes == "")  and             -- Empty description
				(type(symDocs.Notes) == "string") and  -- Docs has a string ...
				(symDocs.Notes ~= "")                  --  ... that is not empty
			)
		) then
			res[symName] = symDocs
			hasSome = true
		end
	end
	if not(hasSome) then
		return nil
	end
	return res
end





--- Fills a_Missing with descriptions that are documented in a_ClassDocs but missing from a_ClassDesc
-- a_ClassDesc is the class' description loaded from APIDesc et al
-- a_ClassDocs is the class' documentation loaded from ToLua++'s parser
local function listMissingClassDescs(a_ClassName, a_ClassDesc, a_ClassDocs, a_Missing)
	local missing =
	{
		Functions = listMissingClassFunctionDescs(a_ClassDesc.Functions, a_ClassDocs.Functions),
		Constants = listMissingClassVarConstDescs(a_ClassDesc.Constants, a_ClassDocs.Constants),
		Variables = listMissingClassVarConstDescs(a_ClassDesc.Variables, a_ClassDocs.Variables),
	}
	if not(missing.Functions) and not(missing.Constants) and not(missing.Variables) then
		-- Nothing missing, don't add anything
		return
	end
	a_Missing[a_ClassName] = missing
end





--- Returns a dictionary of "ClassName" -> { { <desc> }, ... } of descriptions that are documented in a_Docs but missing from a_Descs
-- a_Descs is the descriptions loaded from APIDesc et al
-- a_Docs is the documentation loaded from ToLua++'s parser
local function findMissingDescs(a_Descs, a_Docs)
	local descClasses = a_Descs.Classes
	local res = {}
	for clsName, clsDocs in pairs(a_Docs) do
		local clsDesc = descClasses[clsName] or {}
		listMissingClassDescs(clsName, clsDesc, clsDocs, res)
	end
	return res
end





local function outputTable(a_File, a_Table, a_Indent)
	-- Extract all indices first:
	local allIndices = {}
	for k, _ in pairs(a_Table) do
		table.insert(allIndices, k)
	end
	
	-- Sort the indices:
	table.sort(allIndices,
		function (a_Index1, a_Index2)
			if (type(a_Index1) == "number") then
				if (type(a_Index2) == "number") then
					-- Both indices are numeric, sort by value
					return (a_Index1 < a_Index2)
				end
				-- a_Index2 is non-numeric, always goes after a_Index1
				return true
			end
			if (type(a_Index2) == "number") then
				-- a_Index2 is numeric, a_Index1 is not
				return false
			end
			-- Neither index is numeric, use regular string comparison:
			return caseInsensitiveCompare(tostring(a_Index1), tostring(a_Index2))
		end
	)
	
	-- Output by using the index order:
	a_File:write(a_Indent, "{\n")
	local indent = a_Indent .. "\t"
	for _, index in ipairs(allIndices) do
		-- Write the index:
		a_File:write(indent, "[")
		if (type(index) == "string") then
			a_File:write(string.format("%q", index))
		else
			a_File:write(index)
		end
		a_File:write("] =")
		
		-- Write the value:
		local v = a_Table[index]
		if (type(v) == "table") then
			a_File:write("\n")
			outputTable(a_File, v, indent)
		elseif (type(v) == "string") then
			a_File:write(string.format(" %q", v))
		else
			a_File:write(" ", tostring(v))
		end
		a_File:write(",\n")
	end
	a_File:write(a_Indent, "}")
end





--- Returns a description of function params, as used for output
-- a_Params is nil or an array of parameters from ToLua++'s parser
-- a_ClassMap is a dictionary of "ClassName" -> true for all known classes
local function extractParamsForOutput(a_Params, a_ClassMap)
	if not(a_Params) then
		return ""
	end
	assert(a_ClassMap)
	
	local params = {}
	for _, param in ipairs(a_Params) do
		local paramType = param.Type or ""
		paramType = g_CTypeToLuaType[paramType] or paramType  -- Translate from C type to Lua type
		local paramName = param.Name or paramType or "[unknown]"
		paramName = paramName:gsub("^a_", "")  -- Remove the "a_" prefix, if present
		local idxColon = paramType:find("::")  -- Extract children classes and enums within classes
		local paramTypeAnchor = ""
		if (idxColon) then
			paramTypeAnchor = "#" .. paramType:sub(idxColon + 2)
			paramType = paramType:sub(1, idxColon - 1)
		end
		if (a_ClassMap[paramType]) then
			-- Param type is a class name, make it a link
			if not(param.Name) then
				paramName = "{{" .. paramType .. paramTypeAnchor .. "}}"
			else
				paramName = "{{" .. paramType .. paramTypeAnchor .. "|" .. paramName .. "}}"
			end
		end
		table.insert(params, paramName)
	end
	return table.concat(params, ", ")
end





--- Returns a single line of function description for output
-- a_Desc is the function description
-- a_ClassMap is a dictionary of "ClassName" -> true for all known classes
local function formatFunctionDesc(a_Docs, a_ClassMap)
	local staticClause = ""
	if (a_Docs.IsStatic) then
		staticClause = "IsStatic = true, "
	end
	return string.format("{ Params = %q, Return = %q, %sNotes = %q },\n",
		extractParamsForOutput(a_Docs.Params, a_ClassMap),
		extractParamsForOutput(a_Docs.Returns, a_ClassMap),
		staticClause,
		(a_Docs.Desc or ""):gsub("%.\n", ". "):gsub("\n", ". "):gsub("%s+", " ")
	)
end





--- Outputs differences in function descriptions into a file
-- a_File is the output file
-- a_Functions is nil or a dictionary of "FunctionName" -> { { <desc> }, ... }
-- a_ClassMap is a dictionary of "ClassName" -> true for all known classes
local function outputFunctions(a_File, a_Functions, a_ClassMap)
	assert(a_File)
	if not(a_Functions) then
		return
	end
	
	-- Get a sorted array of all function names:
	local fnNames = {}
	for fnName, _ in pairs(a_Functions) do
		table.insert(fnNames, fnName)
	end
	table.sort(fnNames, caseInsensitiveCompare)
	
	-- Output the function descs:
	a_File:write("\t\tFunctions =\n\t\t{\n")
	for _, fnName in ipairs(fnNames) do
		a_File:write("\t\t\t", g_FunctionNameDocsToDesc[fnName] or fnName, " =")
		local docs = a_Functions[fnName]
		if (docs[2]) then
			-- There are at least two descriptions, use the array format:
			a_File:write("\n\t\t\t{\n")
			for _, doc in ipairs(docs) do
				a_File:write("\t\t\t\t", formatFunctionDesc(doc, a_ClassMap))
			end
			a_File:write("\t\t\t},\n")
		else
			-- There's only one description, use the simpler one-line format:
			a_File:write(" ", formatFunctionDesc(docs[1], a_ClassMap))
		end
	end
	a_File:write("\t\t},\n")
end





--- Returns the description of a single variable or constant
-- a_Docs is the ToLua++'s documentation of the symbol
-- a_ClassMap is a dictionary of "ClassName" -> true for all known classes
local function formatVarConstDesc(a_Docs, a_ClassMap)
	local descType = ""
	if (a_Docs.Type) then
		local luaType = g_CTypeToLuaType[a_Docs.Type] or a_Docs.Type
		if (a_ClassMap[a_Docs.Type]) then
			descType = string.format("Type = {{%q}}, ", luaType);
		else
			descType = string.format("Type = %q, ", luaType);
		end
	end
	return string.format("{ %sNotes = %q },\n", descType, a_Docs.Desc or "")
end





--- Outputs differences in variables' or constants' descriptions into a file
-- a_File is the output file
-- a_VarConst is nil or a dictionary of "VariableOrConstantName" -> { <desc> }
-- a_Header is a string, either "Variables" or "Constants"
-- a_ClassMap is a dictionary of "ClassName" -> true for all known classes
local function outputVarConst(a_File, a_VarConst, a_Header, a_ClassMap)
	assert(a_File)
	assert(type(a_Header) == "string")
	if not(a_VarConst) then
		return
	end
	
	-- Get a sorted array of all symbol names:
	local symNames = {}
	for symName, _ in pairs(a_VarConst) do
		table.insert(symNames, symName)
	end
	table.sort(symNames, caseInsensitiveCompare)
	
	-- Output the symbol descs:
	a_File:write("\t\t", a_Header, " =\n\t\t{\n")
	for _, symName in ipairs(symNames) do
		local docs = a_VarConst[symName]
		a_File:write("\t\t\t", symName, " = ", formatVarConstDesc(docs, a_ClassMap))
	end
	a_File:write("\t\t},\n")
end





--- Outputs the diff into a file
-- a_Diff is the diff calculated by findMissingDescs()
-- The output file is written as a Lua source file formatted to match APIDesc.lua
local function outputDiff(a_Diff)
	-- Sort the classnames:
	local classNames = {}
	local classMap = {}
	for clsName, _ in pairs(a_Diff) do
		table.insert(classNames, clsName)
		classMap[clsName] = true
	end
	table.sort(classNames, caseInsensitiveCompare)
	
	-- Output each class:
	local f = assert(io.open("APIDiff.lua", "w"))
	-- outputTable(f, diff, "")
	f:write("return\n{\n")
	for _, clsName in ipairs(classNames) do
		f:write("\t", clsName, " =\n\t{\n")
		local desc = a_Diff[clsName]
		outputFunctions(f, desc.Functions, classMap)
		outputVarConst(f, desc.Variables, "Variables", classMap)
		outputVarConst(f, desc.Constants, "Constants", classMap)
		f:write("\t},\n")
	end
	f:write("}\n")
	f:close()
end





local apiDesc = loadAPIDesc()
local apiDocs = loadAPIDocs()
local diff = findMissingDescs(apiDesc, apiDocs)
outputDiff(diff)
print("Diff has been output to file APIDiff.lua.")



