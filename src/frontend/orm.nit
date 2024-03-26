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
			var code = "fun orm_read_fields: Array[OrmFieldInfo] do abort"
			var npropdef = toolcontext.parse_propdef(code).as(AMethPropdef)
			nclassdef.n_propdefs.add npropdef
			nclassdef.parent.as(AModule).read_fields_to_fill.add npropdef

			# Stub for the "orm_write_fields" function
			code = "fun orm_write_fields(data : HashMap[String, Object]) do abort"
			npropdef = toolcontext.parse_propdef(code).as(AMethPropdef)
			nclassdef.n_propdefs.add npropdef
			nclassdef.parent.as(AModule).write_fields_to_fill.add npropdef
		end
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
	end

	fun fill_orm_read_fields(nclassdef: AClassdef, method_npropdef: AMethPropdef)
	do
		var npropdefs = nclassdef.n_propdefs

		var code = new Array[String]
		code.add "fun orm_read_fields: Array[OrmFieldInfo]"
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
		code.add "fun orm_write_fields(data : HashMap[String, Object])"
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
end

redef class ADefinition
	redef fun is_field do
		return get_annotations("field").not_empty
	end

	redef fun is_table do
		return get_annotations("table").not_empty
	end
end
