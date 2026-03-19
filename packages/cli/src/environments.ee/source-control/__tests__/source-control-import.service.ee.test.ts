import { Project, type ProjectRepository, User, WorkflowEntity } from '@n8n/db';
import type { FolderRepository } from '@n8n/db';
import type { WorkflowRepository } from '@n8n/db';
import * as fastGlob from 'fast-glob';
import { mock } from 'jest-mock-extended';
import { type InstanceSettings } from 'n8n-core';
import fsp from 'node:fs/promises';

import { SourceControlImportService } from '../source-control-import.service.ee';
import type { SourceControlScopedService } from '../source-control-scoped.service';
import type { ExportableFolder } from '../types/exportable-folders';
import { SourceControlContext } from '../types/source-control-context';

jest.mock('fast-glob');

const globalAdminContext = new SourceControlContext(
	Object.assign(new User(), {
		role: 'global:admin',
	}),
);

const globalMemberContext = new SourceControlContext(
	Object.assign(new User(), {
		role: 'global:member',
	}),
);

describe('SourceControlImportService', () => {
	const workflowRepository = mock<WorkflowRepository>();
	const folderRepository = mock<FolderRepository>();
	const projectRepository = mock<ProjectRepository>();
	const sourceControlScopedService = mock<SourceControlScopedService>();
	const service = new SourceControlImportService(
		mock(),
		mock(),
		mock(),
		mock(),
		mock(),
		projectRepository,
		mock(),
		mock(),
		mock(),
		mock(),
		mock(),
		workflowRepository,
		mock(),
		mock(),
		mock(),
		mock(),
		folderRepository,
		mock<InstanceSettings>({ n8nFolder: '/mock/n8n' }),
		sourceControlScopedService,
	);

	const globMock = fastGlob.default as unknown as jest.Mock<Promise<string[]>, string[]>;
	const fsReadFile = jest.spyOn(fsp, 'readFile');

	beforeEach(() => jest.clearAllMocks());

	describe('getRemoteVersionIdsFromFiles', () => {
		const mockWorkflowFile = '/mock/workflow1.json';
		it('should parse workflow files correctly', async () => {
			globMock.mockResolvedValue([mockWorkflowFile]);

			const mockWorkflowData = {
				id: 'workflow1',
				versionId: 'v1',
				name: 'Test Workflow',
				owner: {
					type: 'personal',
					personalEmail: 'email@email.com',
				},
			};

			fsReadFile.mockResolvedValue(JSON.stringify(mockWorkflowData));
			sourceControlScopedService.getAdminProjectsFromContext.mockResolvedValueOnce([]);

			const result = await service.getRemoteVersionIdsFromFiles(globalAdminContext);
			expect(fsReadFile).toHaveBeenCalledWith(mockWorkflowFile, { encoding: 'utf8' });

			expect(result).toHaveLength(1);
			expect(result[0]).toEqual(
				expect.objectContaining({
					id: 'workflow1',
					versionId: 'v1',
					name: 'Test Workflow',
				}),
			);
		});

		it('should filter out files without valid workflow data', async () => {
			globMock.mockResolvedValue(['/mock/invalid.json']);

			fsReadFile.mockResolvedValue('{}');

			const result = await service.getRemoteVersionIdsFromFiles(globalAdminContext);

			expect(result).toHaveLength(0);
		});
	});

	describe('getRemoteCredentialsFromFiles', () => {
		it('should parse credential files correctly', async () => {
			globMock.mockResolvedValue(['/mock/credential1.json']);

			const mockCredentialData = {
				id: 'cred1',
				name: 'Test Credential',
				type: 'oauth2',
			};

			fsReadFile.mockResolvedValue(JSON.stringify(mockCredentialData));

			const result = await service.getRemoteCredentialsFromFiles(globalAdminContext);

			expect(result).toHaveLength(1);
			expect(result[0]).toEqual(
				expect.objectContaining({
					id: 'cred1',
					name: 'Test Credential',
					type: 'oauth2',
				}),
			);
		});

		it('should filter out files without valid credential data', async () => {
			globMock.mockResolvedValue(['/mock/invalid.json']);
			fsReadFile.mockResolvedValue('{}');

			const result = await service.getRemoteCredentialsFromFiles(globalAdminContext);

			expect(result).toHaveLength(0);
		});
	});

	describe('getRemoteVariablesFromFile', () => {
		it('should parse variables file correctly', async () => {
			globMock.mockResolvedValue(['/mock/variables.json']);

			const mockVariablesData = [
				{ key: 'VAR1', value: 'value1' },
				{ key: 'VAR2', value: 'value2' },
			];

			fsReadFile.mockResolvedValue(JSON.stringify(mockVariablesData));

			const result = await service.getRemoteVariablesFromFile();

			expect(result).toEqual(mockVariablesData);
		});

		it('should return empty array if no variables file found', async () => {
			globMock.mockResolvedValue([]);

			const result = await service.getRemoteVariablesFromFile();

			expect(result).toHaveLength(0);
		});
	});

	describe('getRemoteTagsAndMappingsFromFile', () => {
		it('should parse tags and mappings file correctly', async () => {
			globMock.mockResolvedValue(['/mock/tags.json']);

			const mockTagsData = {
				tags: [{ id: 'tag1', name: 'Tag 1' }],
				mappings: [{ workflowId: 'workflow1', tagId: 'tag1' }],
			};

			fsReadFile.mockResolvedValue(JSON.stringify(mockTagsData));

			const result = await service.getRemoteTagsAndMappingsFromFile(globalAdminContext);

			expect(result.tags).toEqual(mockTagsData.tags);
			expect(result.mappings).toEqual(mockTagsData.mappings);
		});

		it('should return empty tags and mappings if no file found', async () => {
			globMock.mockResolvedValue([]);

			const result = await service.getRemoteTagsAndMappingsFromFile(globalAdminContext);

			expect(result.tags).toHaveLength(0);
			expect(result.mappings).toHaveLength(0);
		});

		it('should return only folder that belong to a project that belongs to the user', async () => {
			globMock.mockResolvedValue(['/mock/tags.json']);

			const mockTagsData = {
				tags: [{ id: 'tag1', name: 'Tag 1' }],
				mappings: [
					{ workflowId: 'workflow1', tagId: 'tag1' },
					{ workflowId: 'workflow2', tagId: 'tag1' },
					{ workflowId: 'workflow3', tagId: 'tag1' },
				],
			};

			workflowRepository.find.mockResolvedValue([
				Object.assign(new WorkflowEntity(), {
					id: 'workflow1',
				}),
				Object.assign(new WorkflowEntity(), {
					id: 'workflow3',
				}),
			]);
			fsReadFile.mockResolvedValue(JSON.stringify(mockTagsData));

			const result = await service.getRemoteTagsAndMappingsFromFile(globalAdminContext);

			expect(result.tags).toEqual(mockTagsData.tags);
			expect(result.mappings).toEqual(mockTagsData.mappings);
		});
	});

	describe('getRemoteFoldersAndMappingsFromFile', () => {
		it('should parse folders and mappings file correctly', async () => {
			globMock.mockResolvedValue(['/mock/folders.json']);

			const now = new Date();

			const mockFoldersData: {
				folders: ExportableFolder[];
			} = {
				folders: [
					{
						id: 'folder1',
						name: 'folder 1',
						parentFolderId: null,
						homeProjectId: 'project1',
						createdAt: now.toISOString(),
						updatedAt: now.toISOString(),
					},
				],
			};

			fsReadFile.mockResolvedValue(JSON.stringify(mockFoldersData));

			const result = await service.getRemoteFoldersAndMappingsFromFile(globalAdminContext);

			expect(result.folders).toEqual(mockFoldersData.folders);
		});

		it('should return empty folders and mappings if no file found', async () => {
			globMock.mockResolvedValue([]);

			const result = await service.getRemoteFoldersAndMappingsFromFile(globalAdminContext);

			expect(result.folders).toHaveLength(0);
		});

		it('should return only folder that belong to a project that belongs to the user', async () => {
			globMock.mockResolvedValue(['/mock/folders.json']);

			const now = new Date();

			const foldersToFind: ExportableFolder[] = [
				{
					id: 'folder1',
					name: 'folder 1',
					parentFolderId: null,
					homeProjectId: 'project1',
					createdAt: now.toISOString(),
					updatedAt: now.toISOString(),
				},
				{
					id: 'folder3',
					name: 'folder 3',
					parentFolderId: null,
					homeProjectId: 'project1',
					createdAt: now.toISOString(),
					updatedAt: now.toISOString(),
				},
				{
					id: 'folder4',
					name: 'folder 3',
					parentFolderId: null,
					homeProjectId: 'project3',
					createdAt: now.toISOString(),
					updatedAt: now.toISOString(),
				},
			];

			const mockFoldersData: {
				folders: ExportableFolder[];
			} = {
				folders: [
					{
						id: 'folder0',
						name: 'folder 0',
						parentFolderId: null,
						homeProjectId: 'project0',
						createdAt: now.toISOString(),
						updatedAt: now.toISOString(),
					},
					...foldersToFind,
					{
						id: 'folder2',
						name: 'folder 2',
						parentFolderId: null,
						homeProjectId: 'project2',
						createdAt: now.toISOString(),
						updatedAt: now.toISOString(),
					},
				],
			};

			sourceControlScopedService.getAdminProjectsFromContext.mockResolvedValue([
				Object.assign(new Project(), {
					id: 'project1',
				}),
				Object.assign(new Project(), {
					id: 'project3',
				}),
			]);
			fsReadFile.mockResolvedValue(JSON.stringify(mockFoldersData));

			const result = await service.getRemoteFoldersAndMappingsFromFile(globalMemberContext);

			expect(result.folders).toEqual(foldersToFind);
		});
	});

	describe('getLocalVersionIdsFromDb', () => {
		const now = new Date();
		jest.useFakeTimers({ now });

		it('should replace invalid updatedAt with current timestamp', async () => {
			const mockWorkflows = [
				{
					id: 'workflow1',
					name: 'Test Workflow',
					updatedAt: 'invalid-date',
				},
			] as unknown as WorkflowEntity[];

			workflowRepository.find.mockResolvedValue(mockWorkflows);

			const result = await service.getLocalVersionIdsFromDb(globalAdminContext);

			expect(result[0].updatedAt).toBe(now.toISOString());
		});
	});

	describe('getLocalFoldersAndMappingsFromDb', () => {
		it('should return data from DB', async () => {
			// Arrange

			folderRepository.find.mockResolvedValue([
				mock({ createdAt: new Date(), updatedAt: new Date() }),
			]);
			workflowRepository.find.mockResolvedValue([mock()]);

			// Act

			const result = await service.getLocalFoldersAndMappingsFromDb(globalAdminContext);

			// Assert

			expect(result.folders).toHaveLength(1);
			expect(result.folders[0]).toHaveProperty('id');
			expect(result.folders[0]).toHaveProperty('name');
			expect(result.folders[0]).toHaveProperty('parentFolderId');
			expect(result.folders[0]).toHaveProperty('homeProjectId');
		});
	});

	describe('importFoldersFromWorkFolder', () => {
		const mockUser = Object.assign(new User(), { id: 'user1' });

		const mockCandidate = {
			file: '/mock/folders.json',
			id: 'folders',
			name: 'folders',
			type: 'folders' as const,
			status: 'modified' as const,
			location: 'remote' as const,
			conflict: false,
			updatedAt: new Date().toISOString(),
		};

		it('should return early if folders array is empty', async () => {
			projectRepository.find.mockResolvedValue([]);
			projectRepository.getPersonalProjectForUserOrFail.mockResolvedValue(
				Object.assign(new Project(), { id: 'personal1' }),
			);
			fsReadFile.mockResolvedValue(JSON.stringify({ folders: [] }));

			const result = await service.importFoldersFromWorkFolder(mockUser, mockCandidate);

			expect(result).toBeUndefined();
			expect(folderRepository.upsert).not.toHaveBeenCalled();
		});

		it('should create folders with the matching homeProject', async () => {
			const now = new Date();
			const mockProject = Object.assign(new Project(), { id: 'project1' });
			const mockPersonalProject = Object.assign(new Project(), { id: 'personal1' });

			projectRepository.find.mockResolvedValue([mockProject]);
			projectRepository.getPersonalProjectForUserOrFail.mockResolvedValue(mockPersonalProject);

			const folder: ExportableFolder = {
				id: 'folder1',
				name: 'Folder 1',
				parentFolderId: null,
				homeProjectId: 'project1',
				createdAt: now.toISOString(),
				updatedAt: now.toISOString(),
			};
			fsReadFile.mockResolvedValue(JSON.stringify({ folders: [folder] }));

			await service.importFoldersFromWorkFolder(mockUser, mockCandidate);

			expect(folderRepository.create).toHaveBeenCalledWith(
				expect.objectContaining({ id: 'folder1', name: 'Folder 1', homeProject: { id: 'project1' } }),
			);
		});

		it('should fall back to personal project if homeProjectId does not match any project', async () => {
			const now = new Date();
			const mockPersonalProject = Object.assign(new Project(), { id: 'personal1' });

			projectRepository.find.mockResolvedValue([]);
			projectRepository.getPersonalProjectForUserOrFail.mockResolvedValue(mockPersonalProject);

			const folder: ExportableFolder = {
				id: 'folder2',
				name: 'Folder 2',
				parentFolderId: null,
				homeProjectId: 'nonexistent-project',
				createdAt: now.toISOString(),
				updatedAt: now.toISOString(),
			};
			fsReadFile.mockResolvedValue(JSON.stringify({ folders: [folder] }));

			await service.importFoldersFromWorkFolder(mockUser, mockCandidate);

			expect(folderRepository.create).toHaveBeenCalledWith(
				expect.objectContaining({ homeProject: { id: 'personal1' } }),
			);
		});

		it('should set up parentFolder relationship after creating folders', async () => {
			const now = new Date();
			const mockProject = Object.assign(new Project(), { id: 'project1' });
			const mockPersonalProject = Object.assign(new Project(), { id: 'personal1' });

			projectRepository.find.mockResolvedValue([mockProject]);
			projectRepository.getPersonalProjectForUserOrFail.mockResolvedValue(mockPersonalProject);

			const parentFolder: ExportableFolder = {
				id: 'parent1',
				name: 'Parent',
				parentFolderId: null,
				homeProjectId: 'project1',
				createdAt: now.toISOString(),
				updatedAt: now.toISOString(),
			};
			const childFolder: ExportableFolder = {
				id: 'child1',
				name: 'Child',
				parentFolderId: 'parent1',
				homeProjectId: 'project1',
				createdAt: now.toISOString(),
				updatedAt: now.toISOString(),
			};
			fsReadFile.mockResolvedValue(JSON.stringify({ folders: [parentFolder, childFolder] }));

			await service.importFoldersFromWorkFolder(mockUser, mockCandidate);

			expect(folderRepository.update).toHaveBeenCalledWith(
				{ id: 'parent1' },
				expect.objectContaining({ parentFolder: null }),
			);
			expect(folderRepository.update).toHaveBeenCalledWith(
				{ id: 'child1' },
				expect.objectContaining({ parentFolder: { id: 'parent1' } }),
			);
		});

		it('should return the imported folders on success', async () => {
			const now = new Date();
			const mockProject = Object.assign(new Project(), { id: 'project1' });
			const mockPersonalProject = Object.assign(new Project(), { id: 'personal1' });

			projectRepository.find.mockResolvedValue([mockProject]);
			projectRepository.getPersonalProjectForUserOrFail.mockResolvedValue(mockPersonalProject);

			const folder: ExportableFolder = {
				id: 'folder1',
				name: 'Folder 1',
				parentFolderId: null,
				homeProjectId: 'project1',
				createdAt: now.toISOString(),
				updatedAt: now.toISOString(),
			};
			fsReadFile.mockResolvedValue(JSON.stringify({ folders: [folder] }));

			const result = await service.importFoldersFromWorkFolder(mockUser, mockCandidate);

			expect(result).toEqual({ folders: [folder] });
		});

		it('should log an error and return undefined on file read failure', async () => {
			projectRepository.find.mockResolvedValue([]);
			projectRepository.getPersonalProjectForUserOrFail.mockResolvedValue(
				Object.assign(new Project(), { id: 'personal1' }),
			);
			fsReadFile.mockRejectedValue(new Error('disk error'));

			const result = await service.importFoldersFromWorkFolder(mockUser, mockCandidate);

			expect(result).toBeUndefined();
			expect(folderRepository.upsert).not.toHaveBeenCalled();
		});
	});
});
