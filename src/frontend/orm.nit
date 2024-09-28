# This file is part of NIT ( http://www.nitlanguage.org ).
#
# Copyright 2024 Olivier Arteau <arteau.olivier@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module orm

private import parser_util
import toolcontext
import phase
import modelize
private import annotation
intrude import literal

redef class ToolContext
	var orm_phase_one: Phase = new OrmPhasePhaseOne(self, null)
	var orm_phase_two: Phase = new OrmPhasePhaseTwo(self, null)
end

private class OrmPhasePhaseOne
	super Phase

	redef fun process_nclassdef(nclassdef)
	do
		# Only look at classes
		if not nclassdef isa AStdClassdef then
			return
		end

		var npropdefs = nclassdef.n_propdefs
		var count_fields_prop = 0

		for attribute in npropdefs do if attribute isa AAttrPropdef then
			if attribute.is_field then
				count_fields_prop += 1
			end
		end

		# Ignore class with no field annotation
		if count_fields_prop > 0 then
			# Stub for the "orm_read_fields" function
			var code = "redef fun orm_read_fields: Array[OrmFieldInfo] do abort"
			var npropdef = toolcontext.parse_propdef(code).as(AMethPropdef)
			nclassdef.n_propdefs.add npropdef
			nclassdef.parent.as(AModule).read_fields_to_fill.add npropdef

			# Stub for the "orm_write_fields" function
			code = "redef fun orm_write_fields(data : HashMap[String, nullable Object]) do abort"
			npropdef = toolcontext.parse_propdef(code).as(AMethPropdef)
			nclassdef.n_propdefs.add npropdef
			nclassdef.parent.as(AModule).write_fields_to_fill.add npropdef

			# Function that return the name of the DB
			var type_name = nclassdef.n_qid.n_id.text
			var actual_name = type_name

			if nclassdef.get_annotations("named").not_empty then
				actual_name = nclassdef.get_annotations("named").first.n_args.first.collect_text
				actual_name = actual_name.substring(1, actual_name.length-2)
			end

			var code_get = new Array[String]
			code_get.add "redef fun orm_get_table: String"
			code_get.add "do"
			code_get.add "	return \"{actual_name}\""
			code_get.add "end"
			npropdef = toolcontext.parse_propdef(code_get.join("\n")).as(AMethPropdef)
			nclassdef.n_propdefs.add npropdef

			code_get = new Array[String]
			code_get.add "redef fun orm_get_type: String"
			code_get.add "do"
			code_get.add "	return \"{type_name}\""
			code_get.add "end"
			npropdef = toolcontext.parse_propdef(code_get.join("\n")).as(AMethPropdef)
			nclassdef.n_propdefs.add npropdef

			# Function that return the name of the primary key
			var primary_key = null

			for attribute in nclassdef.n_propdefs do
				if attribute isa AAttrPropdef and attribute.get_annotations("primary").not_empty then
					primary_key = attribute.name

					if attribute.get_annotations("named").not_empty then
						primary_key = attribute.get_annotations("named").first.n_args.first.collect_text
						primary_key = primary_key.substring(1, primary_key.length-2)
					end
				end
			end

			if primary_key != null then
				code_get = new Array[String]
				code_get.add "redef fun orm_get_primary_key: String"
				code_get.add "do"
				code_get.add "	return \"{primary_key}\""
				code_get.add "end"
				npropdef = toolcontext.parse_propdef(code_get.join("\n")).as(AMethPropdef)
				nclassdef.n_propdefs.add npropdef
			end
		end
	end

	redef fun process_nmodule(nmodule)
	do
		for nclassdef in nmodule.n_classdefs do
			if nclassdef isa AStdClassdef and nclassdef.get_annotations("table").not_empty then
				nmodule.orm_tables.add nclassdef

				# Orm table need to extend from OrmTable so that it's known by the compiler that
				# they implement the main ORM method
				var sc = toolcontext.parse_superclass("OrmTable")
				sc.location = nclassdef.location
				nclassdef.n_propdefs.add sc
			end
		end

		if nmodule.orm_tables.length == 0 then return

		var code = new Array[String]
		code.add "redef class OrmMapper"
		code.add "	redef fun create_class(name) do"
		code.add "		return super"
		code.add "	end"
		code.add "end"

		nmodule.n_classdefs.add toolcontext.parse_classdef(code.join("\n"))
	end

	redef fun process_annotated_node(node, nat)
	do
		var text = nat.n_atid.n_id.text

		if text == "named" then 
			self.process_orm_named(node, nat)
		else if text == "translated_by" then 
			self.process_orm_translated(node, nat)
		else
			return
		end
    end

	fun process_orm_named(node: ANode, nat: AAnnotation)
	do
		var args = nat.n_args
		if args.length != 1 or not args.first isa AStringFormExpr then
			toolcontext.error(node.location,
				"Syntax Error: annotation `named` expects a single string literal as argument.")
			return
		end

		var t = args.first.collect_text
		var val = t.substring(1, t.length-2)
		node.set_orm_actual_name val
	end

	fun process_orm_translated(node: ANode, nat: AAnnotation)
	do
		var args = nat.n_args
		if args.length != 1 or not args.first isa AStringFormExpr then
			toolcontext.error(node.location,
				"Syntax Error: annotation `translated_by` expects a single string literal as argument.")
			return
		end

		var t = args.first.collect_text
		var val = t.substring(1, t.length-2)
		node.set_orm_translator val
	end
end

private class OrmPhasePhaseTwo
	super Phase

	redef fun process_nmodule(nmodule)
	do
		for npropdef in nmodule.read_fields_to_fill do
			var nclassdef = npropdef.parent
			assert nclassdef isa AStdClassdef
			fill_orm_read_fields(nclassdef, npropdef)
		end

		for npropdef in nmodule.write_fields_to_fill do
			var nclassdef = npropdef.parent
			assert nclassdef isa AStdClassdef
			fill_orm_write_fields(nclassdef, npropdef)
		end

		if nmodule.orm_tables.length > 0 then
			fill_create_class(nmodule, nmodule.orm_tables)
		end
	end

	fun fill_create_class(nmodule: AModule, orm_tables: Array[AClassdef]) do
		var orm_mapper_redef = null

		for nclassdef in nmodule.n_classdefs do
			if not nclassdef isa AStdClassdef then continue
			var n_qid = nclassdef.n_qid
			if n_qid != null and n_qid.n_id.text == "OrmMapper" then orm_mapper_redef = nclassdef
		end

		assert orm_mapper_redef != null

		var orm_create_class_method = null

		for npropdef in orm_mapper_redef.n_propdefs do
			if npropdef isa AMethPropdef then
				var id = npropdef.n_methid
				if id isa AIdMethid and id.n_id.text == "create_class" then
					orm_create_class_method = npropdef
				end
			end
		end

		assert orm_create_class_method != null

		var code = new Array[String]
		code.add "redef fun create_class(name)"
		code.add "do"

		for orm_table in orm_tables do
			var concrete_name = orm_table.mclass.name
			code.add "	if name == \"{concrete_name}\" then return new {concrete_name}"
		end
		
		code.add "	return super"
		code.add "end"

		var npropdef = toolcontext.parse_propdef(code.join("\n")).as(AMethPropdef)
		orm_create_class_method.n_block = npropdef.n_block

		# Run the literal phase on the generated code
		var v = new LiteralVisitor(toolcontext)
		v.enter_visit(npropdef.n_block)
	end

	fun fill_orm_read_fields(nclassdef: AClassdef, method_npropdef: AMethPropdef)
	do
		var npropdefs = nclassdef.n_propdefs

		var code = new Array[String]
		code.add "redef fun orm_read_fields: Array[OrmFieldInfo]"
		code.add "do"
		code.add "	var fields = new Array[OrmFieldInfo]"

		for attribute in npropdefs do if attribute isa AAttrPropdef then
			if attribute.is_field then
				if attribute.mtype == null then continue

				var db_field_name = attribute.name
				var class_field_name = attribute.name
				var class_field_type = attribute.mtype.to_s
				var translator = null

				if attribute.get_orm_actual_name != null then db_field_name = attribute.get_orm_actual_name.as(String)
				if attribute.get_orm_translator != null then translator = attribute.get_orm_translator.as(String)

				if translator != null then
					code.add "	var translator_{class_field_name} = new {translator}"
					code.add "	var local_{class_field_name} = translator_{class_field_name}.to_db(self.{class_field_name})"
				else
					code.add "  var local_{class_field_name} = self.{class_field_name}"
					translator = ""
				end

				code.add "	fields.add(new OrmFieldInfo(\"{db_field_name}\", local_{class_field_name}, \"{class_field_type}\", \"{translator}\"))"
			end
		end

		code.add "	return fields"
		code.add "end"

		# Create method Node and add it to the AST
		var npropdef = toolcontext.parse_propdef(code.join("\n")).as(AMethPropdef)
		method_npropdef.n_block = npropdef.n_block

		var v = new LiteralVisitor(toolcontext)
		v.enter_visit(npropdef.n_block)
	end

	fun fill_orm_write_fields(nclassdef: AClassdef, method_npropdef: AMethPropdef)
	do
		var npropdefs = nclassdef.n_propdefs

		var code = new Array[String]
		code.add "redef fun orm_write_fields(data : HashMap[String, nullable Object])"
		code.add "do"

		for attribute in npropdefs do if attribute isa AAttrPropdef then
			if attribute.is_field then
				if attribute.mtype == null then continue

				var db_field_name = attribute.name
				var class_field_name = attribute.name
				var class_field_type = attribute.mtype.to_s
				var translator = null

				if attribute.get_orm_actual_name != null then db_field_name = attribute.get_orm_actual_name.as(String)
				if attribute.get_orm_translator != null then translator = attribute.get_orm_translator.as(String)

				if translator != null then
					code.add "	var translator_{class_field_name} = new {translator}"
					code.add "	var local_{class_field_name} = translator_{class_field_name}.from_db(data[\"{db_field_name}\"])"
				else
					code.add "	var local_{class_field_name} = data[\"{db_field_name}\"].as({class_field_type})"
				end

				code.add "	self.{class_field_name} = local_{class_field_name}"
			end
		end

		code.add "end"

		# Create method Node and add it to the AST
		var npropdef = toolcontext.parse_propdef(code.join("\n")).as(AMethPropdef)
		method_npropdef.n_block = npropdef.n_block

		var v = new LiteralVisitor(toolcontext)
		v.enter_visit(npropdef.n_block)
	end
end

redef class ANode
	var orm_actual_name : nullable String = null
	var orm_translator : nullable String = null

	fun set_orm_actual_name(name : String)
	do
		self.orm_actual_name = name
	end

	fun get_orm_actual_name: nullable String
	do
		return self.orm_actual_name
	end

	fun set_orm_translator(translator : String)
	do
		self.orm_translator = translator
	end

	fun get_orm_translator: nullable String
	do
		return self.orm_translator
	end

	private fun is_field: Bool do return false
	private fun is_table: Bool do return false
end

redef class AModule
	private var read_fields_to_fill = new Array[AMethPropdef]
	private var write_fields_to_fill = new Array[AMethPropdef]
	private var orm_tables = new Array[AClassdef]
end

redef class ADefinition
	redef fun is_field do
		return get_annotations("field").not_empty
	end

	redef fun is_table do
		return get_annotations("table").not_empty
	end
end
