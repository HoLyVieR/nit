# This file is part of NIT (http://www.nitlanguage.org).
#
# Copyright 2014 Alexis Laferrière <alexis.laf@xymus.net>
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

# Implementation of the Message Passing Interface protocol by wrapping OpenMPI
#
# OpenMPI is used only at linking and for it's `mpi.h`. Other implementations
# could be used without much modification.
#
# Supports transfer of any valid `Serializable` instances as well as basic
# C arrays defined in module `c`. Using C arrays is encouraged when performance
# is critical.
#
# Since this module is a thin wrapper around OpenMPI, in case of missing
# documentation, you can refer to https://www.open-mpi.org/doc/v1.8/.
module mpi is
	c_compiler_option(exec("mpicc", "-showme:compile"))
	c_linker_option(exec("mpicc", "-showme:link"))
end

import c
intrude import standard::string
import serialization
private import json_serialization

in "C Header" `{
	#include <mpi.h>
`}

# Handle to most MPI services
class MPI
	# Initialize the MPI execution environment
	init do native_init

	private fun native_init `{ MPI_Init(NULL, NULL); `}

	# Terminates the MPI execution environment
	fun finalize `{ MPI_Finalize(); `}

	# Name of this processor, usually the hostname
	fun processor_name: String import NativeString.to_s_with_length `{
		char *name = malloc(MPI_MAX_PROCESSOR_NAME);
		int size;
		MPI_Get_processor_name(name, &size);
		return NativeString_to_s_with_length(name, size);
	`}

	# Send the content of a buffer
	fun send_from(buffer: Sendable, at, count: Int, dest: Rank, tag: Tag, comm: Comm)
	do
		buffer.send(self, at, count, dest, tag, comm)
	end

	# Send the full content of a buffer
	fun send_all(buffer: Sendable, dest: Rank, tag: Tag, comm: Comm)
	do
		buffer.send_all(self, dest, tag, comm)
	end

	# Efficiently receive data in an existing buffer
	fun recv_into(buffer: Receptacle, at, count: Int, source: Rank, tag: Tag, comm: Comm)
	do
		buffer.recv(self, at, count, source, tag, comm)
	end

	# Efficiently receive data and fill an existing buffer
	fun recv_fill(buffer: Receptacle, source: Rank, tag: Tag, comm: Comm)
	do
		buffer.recv_fill(self, source, tag, comm)
	end

	# Send a complex `Serializable` object
	fun send(data: nullable Serializable, dest: Rank, tag: Tag, comm: Comm)
	do
		# Serialize data
		var stream = new StringOStream
		var serializer = new JsonSerializer(stream)
		serializer.serialize(data)

		# Send message
		var str = stream.to_s
		send_from(str, 0, str.length, dest, tag, comm)
	end

	# Receive a complex object
	fun recv(source: Rank, tag: Tag, comm: Comm): nullable Object
	do
		var status = new Status

		# Block until a message in in queue
		var err = probe(source, tag, comm, status)
		assert err.is_success else print err

		# Get message length
		var count = status.count(new DataType.char)
		assert not count.is_undefined

		# Receive message into buffer
		var buffer = new FlatBuffer.with_capacity(count)
		recv_into(buffer, 0, count, status.source, status.tag, comm)

		# Free our status
		status.free

		# Deserialize message
		var deserializer = new JsonDeserializer(buffer)
		var deserialized = deserializer.deserialize
		
		if deserialized == null then print "|{buffer}|{buffer.chars.join("-")}| {buffer.length}"

		return deserialized
	end

	fun send_empty(dest: Rank, tag: Tag, comm: Comm): SuccessOrError
	`{
		return MPI_Send(NULL, 0, MPI_CHAR, dest, tag, comm);
	`}

	fun recv_empty(dest: Rank, tag: Tag, comm: Comm): SuccessOrError
	`{
		return MPI_Recv(NULL, 0, MPI_CHAR, dest, tag, comm, MPI_STATUS_IGNORE);
	`}

	fun native_send(data: NativeCArray, count: Int, data_type: DataType, dest: Rank, tag: Tag, comm: Comm): SuccessOrError
	`{
		return MPI_Send(data, count, data_type, dest, tag, comm);
	`}

	fun native_recv(data: NativeCArray, count: Int, data_type: DataType, dest: Rank, tag: Tag, comm: Comm, status: Status): SuccessOrError
	`{
		return MPI_Recv(data, count, data_type, dest, tag, comm, status);
	`}

	fun probe(source: Rank, tag: Tag, comm: Comm, status: Status): SuccessOrError
	`{
		return MPI_Probe(source, tag, comm, status);
	`}

	# Synchronize all processors
	fun barrier(comm: Comm) `{ MPI_Barrier(comm); `}

	# Seconds since some time in the past which does not change
	fun wtime: Float `{ return MPI_Wtime(); `}
end

# An MPI communicator
extern class Comm `{ MPI_Comm `}
	new null_ `{ return MPI_COMM_NULL; `}
	new world `{ return MPI_COMM_WORLD; `}
	new self_ `{ return MPI_COMM_SELF; `}

	# Number of processors in this communicator
	fun size: Int `{
		int size;
		MPI_Comm_size(recv, &size);
		return size;
	`}

	# Rank on this processor in this communicator
	fun rank: Rank `{
		int rank;
		MPI_Comm_rank(recv, &rank);
		return rank;
	`}
end

# An MPI data type
extern class DataType `{ MPI_Datatype `}
	new char `{ return MPI_CHAR; `}
	new short `{ return MPI_SHORT; `}
	new int `{ return MPI_INT; `}
	new long `{ return MPI_LONG; `}
	new long_long `{ return MPI_LONG_LONG; `}
	new unsigned_char `{ return MPI_UNSIGNED_CHAR; `}
	new unsigned_short `{ return MPI_UNSIGNED_SHORT; `}
	new unsigned `{ return MPI_UNSIGNED; `}
	new unsigned_long `{ return MPI_UNSIGNED_LONG; `}
	new unsigned_long_long `{ return MPI_UNSIGNED_LONG_LONG; `}
	new float `{ return MPI_FLOAT; `}
	new double `{ return MPI_DOUBLE; `}
	new long_double `{ return MPI_LONG_DOUBLE; `}
	new byte `{ return MPI_BYTE; `}
end

# Status of a communication used by `MPI::probe`
extern class Status `{ MPI_Status* `}
	# Ignore the resulting status
	new ignore `{ return MPI_STATUS_IGNORE; `}

	# Allocated a new `Status`, must be freed with `free`
	new `{ return malloc(sizeof(MPI_Status)); `}

	# Source of this communication
	fun source: Rank `{ return recv->MPI_SOURCE; `}

	# Tag of this communication
	fun tag: Tag `{ return recv->MPI_TAG; `}

	# Success or error on this communication
	fun error: SuccessOrError `{ return recv->MPI_ERROR; `}

	# Count of the given `data_type` in this communication
	fun count(data_type: DataType): Int
	`{
		int count;
		MPI_Get_count(recv, data_type, &count);
		return count;
	`}
end

# An MPI operation
#
# Used with the `reduce` method
extern class Op `{ MPI_Op `}
	new op_null `{ return MPI_OP_NULL; `}
	new max `{ return MPI_MAX; `}
	new min `{ return MPI_MIN; `}
	new sum `{ return MPI_SUM; `}
	new prod `{ return MPI_PROD; `}
	new land `{ return MPI_LAND; `}
	new band `{ return MPI_BAND; `}
	new lor `{ return MPI_LOR; `}
	new bor `{ return MPI_BOR; `}
	new lxor `{ return MPI_LXOR; `}
	new bxor `{ return MPI_BXOR; `}
	new minloc `{ return MPI_MINLOC; `}
	new maxloc `{ return MPI_MAXLOC; `}
	new replace `{ return MPI_REPLACE; `}
end

# An MPI return code to report success or errors
extern class SuccessOrError `{ int `}
	# Is this a success?
	fun is_success: Bool `{ return recv == MPI_SUCCESS; `}

	# Is this an error?
	fun is_error: Bool do return not is_success

	# TODO add is_... for each variant

	# The class of this error
	fun error_class: ErrorClass
	`{
		int class;
		MPI_Error_class(recv, &class);
		return class;
	`}

	redef fun to_s do return native_to_s.to_s
	private fun native_to_s: NativeString `{
		char *err = malloc(MPI_MAX_ERROR_STRING);
		MPI_Error_string(recv, err, NULL);
		return err;
	`}
end

# An MPI error class
extern class ErrorClass `{ int `}
	redef fun to_s do return native_to_s.to_s
	private fun native_to_s: NativeString `{
		char *err = malloc(MPI_MAX_ERROR_STRING);
		MPI_Error_string(recv, err, NULL);
		return err;
	`}
end

# An MPI rank within a communcator
extern class Rank `{ int `}
	new any `{ return MPI_ANY_SOURCE; `}

	# This Rank as an `Int`
	fun to_i: Int `{ return recv; `}
	redef fun to_s do return to_i.to_s
end

# An MPI tag, can be defined using `Int::tag`
extern class Tag `{ int `}
	new any `{ return MPI_ANY_TAG; `}

	# This tag as an `Int`
	fun to_i: Int `{ return recv; `}
	redef fun to_s do return to_i.to_s
end

redef universal Int
	# `self`th MPI rank
	fun rank: Rank `{ return recv; `}

	# Tag identified by `self`
	fun tag: Tag `{ return recv; `}

	# Is this value undefined according to MPI? (may be returned by `Status::count`)
	fun is_undefined: Bool `{ return recv == MPI_UNDEFINED; `}
end

# Something sendable directly and efficiently over MPI
#
# Subclasses of `Sendable` should use the native MPI send function, without
# using Nit serialization.
interface Sendable
	# Type specific send over MPI
	protected fun send(mpi: MPI, at, count: Int, dest: Rank, tag: Tag, comm: Comm) is abstract

	# Type specific send full buffer over MPI
	protected fun send_all(mpi: MPI, dest: Rank, tag: Tag, comm: Comm) is abstract
end


# Something which can receive data directly and efficiently from MPI
#
# Subclasses of `Receptacle` should use the native MPI recveive function,
# without using Nit serialization.
interface Receptacle
	# Type specific receive from MPI
	protected fun recv(mpi: MPI, at, count: Int, source: Rank, tag: Tag, comm: Comm) is abstract

	# Type specific receive and fill buffer from MPI
	protected fun recv_fill(mpi: MPI, source: Rank, tag: Tag, comm: Comm) is abstract
end

redef class CArray[E]
	super Sendable
	super Receptacle
end

redef class Text
	super Sendable

	redef fun send(mpi, at, count, dest, tag, comm)
	do
		var str
		if at != 0 or count != length then
			str = substring(at, count)
		else str = self

		mpi.native_send(str.to_cstring, count, new DataType.char,
			dest, tag, new Comm.world)
	end

	redef fun send_all(mpi, dest, tag, comm) do send(mpi, 0, length, dest, tag, comm)
end

redef class FlatBuffer
	super Receptacle

	redef fun recv(mpi, at, count, source, tag, comm)
	do
		var min_capacity = at + count
		if capacity < min_capacity then enlarge min_capacity

		var array
		if at != 0 then
			array = items + at
		else array = items

		mpi.native_recv(array, count, new DataType.char,
			source, tag, new Comm.world, new Status.ignore)

		length = capacity
		is_dirty = true
	end

	redef fun recv_fill(mpi, dest, tag, comm) do recv(mpi, 0, capacity, dest, tag, comm)
end

redef class CIntArray
	redef fun send(mpi, at, count, dest, tag, comm)
	do
		var array
		if at != 0 then
			array = native_array + at
		else array = native_array

		mpi.native_send(array, count, new DataType.int,
			dest, tag, new Comm.world)
	end

	redef fun send_all(mpi, dest, tag, comm) do send(mpi, 0, length, dest, tag, comm)

	redef fun recv(mpi, at, count, source, tag, comm)
	do
		var array
		if at != 0 then
			array = native_array + at
		else array = native_array

		mpi.native_recv(array, count, new DataType.int,
			source, tag, new Comm.world, new Status.ignore)
	end

	redef fun recv_fill(mpi, dest, tag, comm) do recv(mpi, 0, length, dest, tag, comm)
end

# Shortcut to the world communicator (same as `new Comm.world`)
fun comm_world: Comm do return once new Comm.world