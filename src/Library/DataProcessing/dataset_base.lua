local requireRel
if arg and arg[0] then
    package.path = arg[0]:match("(.-)[^\\/]+$") .. "?.lua;" .. package.path
    requireRel = require
elseif ... then
    local d = (...):match("(.-)[^%.]+$")
    function requireRel(module) return require(d .. module) end
end


require 'torch'
require 'cutorch'
local ffi_cuda = require 'ffi'
ffi_cuda.cdef[[
typedef struct{	char **strings;	size_t len; size_t ind;} batchInfo;
batchInfo* createBatchInfo(int batch_size);
void deleteBatchInfo(batchInfo* binfo);
void pushProteinToBatchInfo(const char* filename, batchInfo* binfo);
void printBatchInfo(batchInfo* binfo);

int loadProteinCUDA(THCState *state,
					batchInfo* batch, THCudaTensor *batch5D,
					bool shift, bool rot, float resolution,
					int assigner_type, int spatial_dim);


]]
local Cuda = ffi_cuda.load'../Library/build/libload_protein_cuda.so'

torch.setdefaulttensortype('torch.FloatTensor')

requireRel('./utils.lua')

cDatasetBase = {}
cDatasetBase.__index = cDatasetBase

function cDatasetBase.new(batch_size, input_size, augment_rotate, augment_shift, resolution, binary)
	local self = setmetatable({}, cDatasetBase)
	self.__index = self
	self:init_variables(batch_size, input_size, augment_rotate, augment_shift, resolution, binary)
	return self
end

function cDatasetBase.init_variables(self, batch_size, input_size, augment_rotate, augment_shift, resolution, binary)
	self.batch_size = batch_size
	self.input_size = input_size
	if augment_rotate==nil then 
		augment_rotate = false
	end
	self.rotate = augment_rotate
	if augment_shift==nil then 
		augment_shift = false
	end
	self.shift = augment_shift
	if resolution==nil then 
		resolution = 1.0
	end
	self.resolution = resolution
	if binary==nil then
		binary = false
	end
	self.binary = binary

	self.batch = torch.zeros(self.batch_size, self.input_size[1], 
		self.input_size[2], self.input_size[3], self.input_size[4]):cuda()
	self.indexes = torch.zeros(self.batch_size):type('torch.IntTensor')

	self.num_atom_types = self.input_size[1]
	self.assigner_type = nil
	if self.num_atom_types == 4 then 
		self.assigner_type = 1
	end
	if self.num_atom_types == 11 then 
		self.assigner_type = 2
	end
end
function cDatasetBase.load_proteins(self, description_filename)
	--PROTEINS:
	--dataset.proteins{
	--	index: protein name
	--	index: protein name
	--	...
	--}
	local f = io.input(description_filename)
	for line in io.lines() do
		table.insert(self.proteins,line)
		self.decoys[line]={}
	end
	f:close()
end

function cDatasetBase.load_protein_decoys(self, protein, description_directory)
	--DECOYS:
	--dataset.decoys{
	--	protein1: {
	--		decoy1_path, rmsd, tm-score, gdt-ts, gdt-ha	
	--		decoy2_path, rmsd, tm-score, gdt-ts, gdt-ha	
	--		...
	--	}	
	--	protein2: {
	--		decoy1_path, rmsd, tm-score, gdt-ts, gdt-ha	
	--		decoy2_path, rmsd, tm-score, gdt-ts, gdt-ha	
	--		...
	--	}	
	--	...
	--}
	local f = io.input(description_directory..'/'..protein..'.dat')
	io.read()
	for line in io.lines() do
		a = split(line,'\t')
		table.insert(self.decoys[protein],{filename = a[1],
										rmsd = tonumber(a[2]), 
										tm_score = tonumber(a[3]), 
										gdt_ts = tonumber(a[4]), 
										gdt_ha = tonumber(a[5])
										}
					)
		if tonumber(a[2])==nil or tonumber(a[3])==nil or tonumber(a[4])==nil or tonumber(a[5])==nil then 
			print('Error in', a[1])
		end
	end
	f:close()
end

function cDatasetBase.load_dataset(self, description_directory, description_filename)
	self.proteins = {}
	self.decoys = {}
	
	print('Loading dataset: '..description_directory)
	
	if description_filename == nil then
		description_filename = 'datasetDescription.dat'
	end

	self:load_proteins(description_directory..'/'..description_filename)
	for i=1,#self.proteins do
		self:load_protein_decoys(self.proteins[i], description_directory)
	end

end

function cDatasetBase.shuffle_dataset(self)
	shuffleTable(self.proteins)
	for i=1,#self.proteins do
		shuffleTable(self.decoys[self.proteins[i]])
	end
end

function cDatasetBase.load_sequential_batch(self, protein_name, num_beg)
	self.batch:fill(0.0)
	self.indexes:fill(0)	
	local num_end = math.min(#self.decoys[protein_name],num_beg+self.batch_size-1)
		
	local batch_ind = 1
	
	local batch_info = Cuda.createBatchInfo(num_end - num_beg + 1)
	for ind = num_beg, num_end do
		Cuda.pushProteinToBatchInfo(self.decoys[protein_name][ind].filename, batch_info)
		
		self.indexes[batch_ind] = ind
		batch_ind=batch_ind+1
	end
	local res = Cuda.loadProteinCUDA(	cutorch.getState(), batch_info, self.batch:cdata(), 
							self.shift, self.rotate, self.resolution, 
							self.assigner_type, self.input_size[2])
	if res<0 then 
		print('Throwing error')
		error() 
	end
	Cuda.deleteBatchInfo(batch_info)

	return self.batch, self.indexes
end

function cDatasetBase.load_batch_repeat(self, decoy_filename)
	self.batch:fill(0.0)
	local batch_info = Cuda.createBatchInfo(self.batch_size)
	for ind = 1, self.batch_size do
		Cuda.pushProteinToBatchInfo(decoy_filename, batch_info)
	end
	local res = Cuda.loadProteinCUDA(	cutorch.getState(), batch_info, self.batch:cdata(), 
							self.shift, self.rotate, self.resolution, 
							self.assigner_type, self.input_size[2])
	if res<0 then error() end
	Cuda.deleteBatchInfo(batch_info)

	return self.batch
end

