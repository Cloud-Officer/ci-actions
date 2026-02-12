const axios = require('axios');
const core = require('@actions/core');

jest.mock('axios');
jest.mock('@actions/core');

const { run, COLORS } = require('./index');

describe('Slack Action', () => {
  const originalEnv = process.env;

  beforeEach(() => {
    jest.clearAllMocks();

    process.env = {
      ...originalEnv,
      GITHUB_SERVER_URL: 'https://github.com',
      GITHUB_REPOSITORY: 'Cloud-Officer/ci-actions',
      GITHUB_RUN_ID: '12345',
      GITHUB_RUN_NUMBER: '42',
      GITHUB_SHA: 'abc123def456',
      GITHUB_EVENT_NAME: 'push',
      GITHUB_REF: 'refs/heads/main',
      GITHUB_ACTOR: 'testuser'
    };

    axios.post.mockResolvedValue({ data: { ok: true } });
  });

  afterEach(() => {
    process.env = originalEnv;
  });

  describe('COLORS', () => {
    it('should export correct color values', () => {
      expect(COLORS.info).toBe('#439FE0');
      expect(COLORS.success).toBe('#5cb589');
      expect(COLORS.failure).toBe('#d5001a');
      expect(COLORS.warning).toBe('#f8c753');
    });
  });

  describe('run()', () => {
    it('should throw error for invalid JSON input', async () => {
      core.getInput.mockImplementation((name) => {
        if (name === 'webhook-url') return 'https://hooks.slack.com/test';
        if (name === 'jobs') return 'invalid json';
        return '';
      });

      await expect(run()).rejects.toThrow("Failed to parse 'jobs' input as JSON");
    });

    it('should truncate long invalid JSON in error message', async () => {
      const longInvalidJson = 'x'.repeat(200);

      core.getInput.mockImplementation((name) => {
        if (name === 'webhook-url') return 'https://hooks.slack.com/test';
        if (name === 'jobs') return longInvalidJson;
        return '';
      });

      await expect(run()).rejects.toThrow('...');
    });

    it('should send message for successful jobs', async () => {
      const jobs = {
        variables: { outputs: { COMMIT_MESSAGE: 'Test commit' } },
        build: { result: 'success' },
        test: { result: 'success' }
      };

      core.getInput.mockImplementation((name) => {
        if (name === 'webhook-url') return 'https://hooks.slack.com/test';
        if (name === 'jobs') return JSON.stringify(jobs);
        return '';
      });

      await run();

      expect(axios.post).toHaveBeenCalledWith(
        'https://hooks.slack.com/test',
        expect.objectContaining({
          attachments: expect.arrayContaining([
            expect.objectContaining({
              color: '#439FE0'
            })
          ])
        }),
        { timeout: 30000 }
      );
    });

    it('should use failure color when a job fails', async () => {
      const jobs = {
        variables: { outputs: { COMMIT_MESSAGE: 'Test commit' } },
        build: { result: 'success' },
        test: { result: 'failure' }
      };

      core.getInput.mockImplementation((name) => {
        if (name === 'webhook-url') return 'https://hooks.slack.com/test';
        if (name === 'jobs') return JSON.stringify(jobs);
        return '';
      });

      await run();

      expect(axios.post).toHaveBeenCalledWith(
        'https://hooks.slack.com/test',
        expect.objectContaining({
          attachments: expect.arrayContaining([
            expect.objectContaining({
              color: '#d5001a'
            })
          ])
        }),
        { timeout: 30000 }
      );
    });

    it('should use warning color when a job is cancelled', async () => {
      const jobs = {
        variables: { outputs: { COMMIT_MESSAGE: 'Test commit' } },
        build: { result: 'cancelled' }
      };

      core.getInput.mockImplementation((name) => {
        if (name === 'webhook-url') return 'https://hooks.slack.com/test';
        if (name === 'jobs') return JSON.stringify(jobs);
        return '';
      });

      await run();

      expect(axios.post).toHaveBeenCalledWith(
        'https://hooks.slack.com/test',
        expect.objectContaining({
          attachments: expect.arrayContaining([
            expect.objectContaining({
              color: '#f8c753'
            })
          ])
        }),
        { timeout: 30000 }
      );
    });

    it('should handle skipped jobs with success color', async () => {
      const jobs = {
        variables: { outputs: { COMMIT_MESSAGE: 'Test commit' } },
        build: { result: 'skipped' }
      };

      core.getInput.mockImplementation((name) => {
        if (name === 'webhook-url') return 'https://hooks.slack.com/test';
        if (name === 'jobs') return JSON.stringify(jobs);
        return '';
      });

      await run();

      expect(axios.post).toHaveBeenCalledWith(
        'https://hooks.slack.com/test',
        expect.objectContaining({
          attachments: expect.arrayContaining([
            expect.objectContaining({
              color: '#5cb589'
            })
          ])
        }),
        { timeout: 30000 }
      );
    });

    it('should include DEPLOY_ flags in message', async () => {
      const jobs = {
        variables: {
          outputs: {
            COMMIT_MESSAGE: 'Test commit',
            DEPLOY_ON_BETA: '1',
            DEPLOY_ON_PROD: '0',
            SKIP_TESTS: '1'
          }
        },
        build: { result: 'success' }
      };

      core.getInput.mockImplementation((name) => {
        if (name === 'webhook-url') return 'https://hooks.slack.com/test';
        if (name === 'jobs') return JSON.stringify(jobs);
        return '';
      });

      await run();

      const callArg = axios.post.mock.calls[0][1];
      const allFields = callArg.attachments
        .flatMap(a => a.blocks || [])
        .flatMap(b => b.fields || [])
        .map(f => f.text);

      expect(allFields).toContain(':heavy_check_mark: DEPLOY_ON_BETA');
      expect(allFields).toContain(':heavy_check_mark: SKIP_TESTS');
      expect(allFields).not.toContain(':heavy_check_mark: DEPLOY_ON_PROD');
    });

    it('should not include flags that are set to 0', async () => {
      const jobs = {
        variables: {
          outputs: {
            COMMIT_MESSAGE: 'Test commit',
            DEPLOY_ON_BETA: '0',
            DEPLOY_ON_PROD: '0'
          }
        },
        build: { result: 'success' }
      };

      core.getInput.mockImplementation((name) => {
        if (name === 'webhook-url') return 'https://hooks.slack.com/test';
        if (name === 'jobs') return JSON.stringify(jobs);
        return '';
      });

      await run();

      const callArg = axios.post.mock.calls[0][1];
      const firstAttachment = callArg.attachments[0];
      const hasDeployFields = firstAttachment.blocks.some(block =>
        block.fields && block.fields.some(field =>
          field.text && field.text.includes('DEPLOY_')
        )
      );
      expect(hasDeployFields).toBe(false);
    });

    it('should handle missing variables outputs gracefully', async () => {
      const jobs = {
        build: { result: 'success' }
      };

      core.getInput.mockImplementation((name) => {
        if (name === 'webhook-url') return 'https://hooks.slack.com/test';
        if (name === 'jobs') return JSON.stringify(jobs);
        return '';
      });

      await run();

      expect(axios.post).toHaveBeenCalled();
    });

    it('should handle empty jobs object', async () => {
      const jobs = {};

      core.getInput.mockImplementation((name) => {
        if (name === 'webhook-url') return 'https://hooks.slack.com/test';
        if (name === 'jobs') return JSON.stringify(jobs);
        return '';
      });

      await run();

      expect(axios.post).toHaveBeenCalled();
    });

    it('should propagate axios errors', async () => {
      const jobs = {
        build: { result: 'success' }
      };

      core.getInput.mockImplementation((name) => {
        if (name === 'webhook-url') return 'https://hooks.slack.com/test';
        if (name === 'jobs') return JSON.stringify(jobs);
        return '';
      });

      axios.post.mockRejectedValue(new Error('Network error'));

      await expect(run()).rejects.toThrow('Network error');
    });

    it('should group jobs in pairs for display', async () => {
      const jobs = {
        variables: { outputs: { COMMIT_MESSAGE: 'Test' } },
        job1: { result: 'success' },
        job2: { result: 'success' },
        job3: { result: 'success' }
      };

      core.getInput.mockImplementation((name) => {
        if (name === 'webhook-url') return 'https://hooks.slack.com/test';
        if (name === 'jobs') return JSON.stringify(jobs);
        return '';
      });

      await run();

      const callArg = axios.post.mock.calls[0][1];
      expect(callArg.attachments.length).toBeGreaterThan(1);
    });

    it('should use correct emoji for each job status', async () => {
      const jobs = {
        variables: { outputs: { COMMIT_MESSAGE: 'Test' } },
        successJob: { result: 'success' },
        failureJob: { result: 'failure' },
        cancelledJob: { result: 'cancelled' },
        skippedJob: { result: 'skipped' },
        unknownJob: { result: 'unknown' }
      };

      core.getInput.mockImplementation((name) => {
        if (name === 'webhook-url') return 'https://hooks.slack.com/test';
        if (name === 'jobs') return JSON.stringify(jobs);
        return '';
      });

      await run();

      const callArg = axios.post.mock.calls[0][1];
      const allFields = callArg.attachments
        .flatMap(a => a.blocks || [])
        .flatMap(b => b.fields || [])
        .map(f => f.text);

      expect(allFields).toContain(':white_check_mark: successJob');
      expect(allFields).toContain(':x: failureJob');
      expect(allFields).toContain(':hand: cancelledJob');
      expect(allFields).toContain(':heavy_minus_sign: skippedJob');
      expect(allFields).toContain(':question: unknownJob');
    });

    it('should include commit message in context', async () => {
      const jobs = {
        variables: {
          outputs: {
            COMMIT_MESSAGE: 'feat: Add new feature'
          }
        },
        build: { result: 'success' }
      };

      core.getInput.mockImplementation((name) => {
        if (name === 'webhook-url') return 'https://hooks.slack.com/test';
        if (name === 'jobs') return JSON.stringify(jobs);
        return '';
      });

      await run();

      const callArg = axios.post.mock.calls[0][1];
      const contextBlocks = callArg.attachments[0].blocks.filter(b => b.type === 'context');
      const hasCommitMessage = contextBlocks.some(block =>
        block.elements.some(el => el.text === 'feat: Add new feature')
      );
      expect(hasCommitMessage).toBe(true);
    });

    it('should include build link with correct URL', async () => {
      const jobs = {
        variables: { outputs: {} },
        build: { result: 'success' }
      };

      core.getInput.mockImplementation((name) => {
        if (name === 'webhook-url') return 'https://hooks.slack.com/test';
        if (name === 'jobs') return JSON.stringify(jobs);
        return '';
      });

      await run();

      const callArg = axios.post.mock.calls[0][1];
      const sectionBlock = callArg.attachments[0].blocks.find(b =>
        b.type === 'section' && b.text
      );
      expect(sectionBlock.text.text).toContain('https://github.com/Cloud-Officer/ci-actions/actions/runs/12345');
      expect(sectionBlock.text.text).toContain('Build #42');
    });

    it('should handle UPDATE_ prefix flags', async () => {
      const jobs = {
        variables: {
          outputs: {
            COMMIT_MESSAGE: 'Test',
            UPDATE_PACKAGES: '1'
          }
        },
        build: { result: 'success' }
      };

      core.getInput.mockImplementation((name) => {
        if (name === 'webhook-url') return 'https://hooks.slack.com/test';
        if (name === 'jobs') return JSON.stringify(jobs);
        return '';
      });

      await run();

      const callArg = axios.post.mock.calls[0][1];
      const allFields = callArg.attachments
        .flatMap(a => a.blocks || [])
        .flatMap(b => b.fields || [])
        .map(f => f.text);

      expect(allFields).toContain(':heavy_check_mark: UPDATE_PACKAGES');
    });

    it('should handle single job remaining after pairs', async () => {
      const jobs = {
        variables: { outputs: { COMMIT_MESSAGE: 'Test' } },
        job1: { result: 'success' }
      };

      core.getInput.mockImplementation((name) => {
        if (name === 'webhook-url') return 'https://hooks.slack.com/test';
        if (name === 'jobs') return JSON.stringify(jobs);
        return '';
      });

      await run();

      const callArg = axios.post.mock.calls[0][1];
      const jobAttachments = callArg.attachments.slice(1);
      expect(jobAttachments.length).toBe(1);
      expect(jobAttachments[0].blocks[0].fields.length).toBe(1);
    });

    it('should reset color after failure in pairs', async () => {
      const jobs = {
        variables: { outputs: { COMMIT_MESSAGE: 'Test' } },
        failJob: { result: 'failure' },
        successJob1: { result: 'success' },
        successJob2: { result: 'success' },
        successJob3: { result: 'success' }
      };

      core.getInput.mockImplementation((name) => {
        if (name === 'webhook-url') return 'https://hooks.slack.com/test';
        if (name === 'jobs') return JSON.stringify(jobs);
        return '';
      });

      await run();

      const callArg = axios.post.mock.calls[0][1];
      const jobAttachments = callArg.attachments.slice(1);

      const hasFailureColor = jobAttachments.some(a => a.color === '#d5001a');
      const hasSuccessColor = jobAttachments.some(a => a.color === '#5cb589');

      expect(hasFailureColor).toBe(true);
      expect(hasSuccessColor).toBe(true);
    });

    it('should include repository info in context', async () => {
      const jobs = {
        variables: { outputs: {} },
        build: { result: 'success' }
      };

      core.getInput.mockImplementation((name) => {
        if (name === 'webhook-url') return 'https://hooks.slack.com/test';
        if (name === 'jobs') return JSON.stringify(jobs);
        return '';
      });

      await run();

      const callArg = axios.post.mock.calls[0][1];
      const contextBlocks = callArg.attachments[0].blocks.filter(b => b.type === 'context');
      const hasRepoInfo = contextBlocks.some(block =>
        block.elements.some(el =>
          el.text && el.text.includes('Cloud-Officer/ci-actions') && el.text.includes('testuser')
        )
      );
      expect(hasRepoInfo).toBe(true);
    });

    it('should handle empty commit message', async () => {
      const jobs = {
        variables: { outputs: {} },
        build: { result: 'success' }
      };

      core.getInput.mockImplementation((name) => {
        if (name === 'webhook-url') return 'https://hooks.slack.com/test';
        if (name === 'jobs') return JSON.stringify(jobs);
        return '';
      });

      await run();

      const callArg = axios.post.mock.calls[0][1];
      const contextBlocks = callArg.attachments[0].blocks.filter(b => b.type === 'context');
      const hasEmptyCommitMessage = contextBlocks.some(block =>
        block.elements.some(el => el.type === 'plain_text' && el.text === '')
      );
      expect(hasEmptyCommitMessage).toBe(true);
    });
  });
});
