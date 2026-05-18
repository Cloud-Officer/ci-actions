const axios = require('axios');
const core = require('@actions/core');

jest.mock('axios');
jest.mock('@actions/core');

const { run, COLORS, githubEnv, reportError } = require('./index');

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

    it('should reject jobs that is a JSON array', async () => {
      core.getInput.mockImplementation((name) => {
        if (name === 'webhook-url') return 'https://hooks.slack.com/test';
        if (name === 'jobs') return JSON.stringify([{ result: 'success' }]);
        return '';
      });

      await expect(run()).rejects.toThrow("'jobs' input must be a JSON object keyed by job name, but got array");
    });

    it('should reject jobs that is a JSON primitive', async () => {
      core.getInput.mockImplementation((name) => {
        if (name === 'webhook-url') return 'https://hooks.slack.com/test';
        if (name === 'jobs') return '"oops"';
        return '';
      });

      await expect(run()).rejects.toThrow("'jobs' input must be a JSON object keyed by job name, but got string");
    });

    it('should reject jobs that is JSON null', async () => {
      core.getInput.mockImplementation((name) => {
        if (name === 'webhook-url') return 'https://hooks.slack.com/test';
        if (name === 'jobs') return 'null';
        return '';
      });

      await expect(run()).rejects.toThrow("'jobs' input must be a JSON object keyed by job name, but got null");
    });

    it('should reject a job entry that is not an object', async () => {
      core.getInput.mockImplementation((name) => {
        if (name === 'webhook-url') return 'https://hooks.slack.com/test';
        if (name === 'jobs') return JSON.stringify({ build: 'success' });
        return '';
      });

      await expect(run()).rejects.toThrow("'jobs.build' must be an object (e.g. { \"result\": \"success\" }), but got string");
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
              color: COLORS.info
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
              color: COLORS.failure
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
              color: COLORS.warning
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
              color: COLORS.success
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

// The action runs `dist/index.js` (the ncc bundle), not index.js. `pretest`
// rebuilds and fails on a stale dist; this asserts the shipped artifact is
// actually loadable and exposes the expected API, catching a bad ncc upgrade
// or tree-shake regression that source-only tests would miss.
describe('built bundle (dist/index.js)', () => {
  it('loads and exports the public API', () => {
    jest.isolateModules(() => {
      const dist = require('./dist/index.js');
      expect(typeof dist.run).toBe('function');
      expect(typeof dist.validateJobs).toBe('function');
      expect(dist.COLORS).toEqual({
        info: '#439FE0',
        success: '#5cb589',
        failure: '#d5001a',
        warning: '#f8c753'
      });
    });
  });

  it('enforces jobs validation in the bundled code', () => {
    jest.isolateModules(() => {
      const dist = require('./dist/index.js');
      expect(() => dist.validateJobs([])).toThrow('must be a JSON object keyed by job name');
      expect(() => dist.validateJobs({ build: { result: 'success' } })).not.toThrow();
    });
  });
});

describe('error handling and env hardening', () => {
  const originalEnv = process.env;

  beforeEach(() => {
    jest.clearAllMocks();
    process.env = {
      ...originalEnv,
      GITHUB_SERVER_URL: 'https://github.com',
      GITHUB_REPOSITORY: 'Cloud-Officer/ci-actions',
      GITHUB_RUN_ID: '12345',
      GITHUB_RUN_NUMBER: '42',
      GITHUB_SHA: 'abc123',
      GITHUB_EVENT_NAME: 'push',
      GITHUB_REF: 'refs/heads/main',
      GITHUB_ACTOR: 'tester'
    };
  });

  afterEach(() => {
    process.env = originalEnv;
  });

  it('rejects when webhook-url is empty (TEST-005)', async () => {
    core.getInput.mockImplementation((name) => {
      if (name === 'webhook-url') return '';
      if (name === 'jobs') return JSON.stringify({ build: { result: 'success' } });
      return '';
    });

    await expect(run()).rejects.toThrow("'webhook-url' input is required but was empty");
    expect(axios.post).not.toHaveBeenCalled();
  });

  it('propagates an axios timeout (TEST-005)', async () => {
    core.getInput.mockImplementation((name) => {
      if (name === 'webhook-url') return 'https://hooks.slack.com/test';
      if (name === 'jobs') return JSON.stringify({ build: { result: 'success' } });
      return '';
    });
    const timeout = new Error('timeout of 30000ms exceeded');
    timeout.code = 'ECONNABORTED';
    axios.post.mockRejectedValue(timeout);

    await expect(run()).rejects.toThrow('timeout of 30000ms exceeded');
  });

  it('reportError surfaces the Slack 4xx response body and stack (BUG-023)', () => {
    const error = new Error('Request failed with status code 400');
    error.response = { status: 400, data: { error: 'invalid_payload' } };

    reportError(error);

    expect(core.error).toHaveBeenCalledWith(error.stack);
    expect(core.error).toHaveBeenCalledWith('Response body: {"error":"invalid_payload"}');
    expect(core.setFailed).toHaveBeenCalledWith('Request failed with status code 400');
  });

  it('reportError handles a plain error without a response (QUAL-021)', () => {
    const error = new Error('boom');

    reportError(error);

    expect(core.error).toHaveBeenCalledWith(error.stack);
    expect(core.setFailed).toHaveBeenCalledWith('boom');
  });

  it('reportError handles a non-Error rejection value (QUAL-021)', () => {
    reportError('string failure');

    expect(core.setFailed).toHaveBeenCalledWith('string failure');
  });

  it('run().catch(reportError) wires a 4xx through to setFailed (BUG-023)', async () => {
    core.getInput.mockImplementation((name) => {
      if (name === 'webhook-url') return 'https://hooks.slack.com/test';
      if (name === 'jobs') return JSON.stringify({ build: { result: 'success' } });
      return '';
    });
    const error = new Error('Request failed with status code 400');
    error.response = { status: 400, data: { error: 'channel_not_found' } };
    axios.post.mockRejectedValue(error);

    await run().catch(reportError);

    expect(core.error).toHaveBeenCalledWith('Response body: {"error":"channel_not_found"}');
    expect(core.setFailed).toHaveBeenCalledWith('Request failed with status code 400');
  });

  it('githubEnv returns the value when set and a placeholder when unset (BUG-024)', () => {
    process.env.GITHUB_REPOSITORY = 'Cloud-Officer/ci-actions';
    delete process.env.GITHUB_SERVER_URL;

    expect(githubEnv('GITHUB_REPOSITORY')).toBe('Cloud-Officer/ci-actions');
    expect(githubEnv('GITHUB_SERVER_URL')).toBe('?');
  });

  it('does not render "undefined" in the payload when GITHUB_* are missing (BUG-024)', async () => {
    delete process.env.GITHUB_SERVER_URL;
    delete process.env.GITHUB_REPOSITORY;
    delete process.env.GITHUB_RUN_ID;
    core.getInput.mockImplementation((name) => {
      if (name === 'webhook-url') return 'https://hooks.slack.com/test';
      if (name === 'jobs') return JSON.stringify({ build: { result: 'success' } });
      return '';
    });
    axios.post.mockResolvedValue({ data: { ok: true } });

    await run();

    const payload = JSON.stringify(axios.post.mock.calls[0][1]);
    expect(payload).not.toContain('undefined');
  });
});
