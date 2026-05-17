const core = require('@actions/core');
const axios = require("axios");

const COLORS = {
    info: '#439FE0',
    success: '#5cb589',
    failure: '#d5001a',
    warning: '#f8c753'
};

// GitHub Actions populates GITHUB_* at runtime; when run outside Actions
// (local debugging) they are undefined and would render "https://undefined/..."
// in the Slack payload. Fall back to a visible placeholder instead.
function githubEnv(name) {
    return process.env[name] || '?';
}

// Lightweight runtime validation of the parsed `jobs` payload. The input is
// `${{toJSON(needs)}}` - an object keyed by job name whose values are objects
// (e.g. { "result": "success", "outputs": {...} }). Without this, a shape
// change (array, renamed key, string value) silently produces wrong output
// instead of failing fast with an actionable message.
function validateJobs(jobs) {
    const describe = (value) => (value === null ? 'null' : Array.isArray(value) ? 'array' : typeof value);

    if (jobs === null || typeof jobs !== 'object' || Array.isArray(jobs)) {
        throw new Error(`'jobs' input must be a JSON object keyed by job name, but got ${describe(jobs)}`);
    }

    for (const [jobName, job] of Object.entries(jobs)) {
        if (job === null || typeof job !== 'object' || Array.isArray(job)) {
            throw new Error(`'jobs.${jobName}' must be an object (e.g. { "result": "success" }), but got ${describe(job)}`);
        }
    }
}

function parseInputs() {
    const webhookUrl = core.getInput('webhook-url');
    if (!webhookUrl) {
        throw new Error("'webhook-url' input is required but was empty");
    }
    const jobsInput = core.getInput('jobs');
    let jobs;
    try {
        jobs = JSON.parse(jobsInput);
    } catch (parseError) {
        throw new Error(`Failed to parse 'jobs' input as JSON: ${parseError.message}. Input was: ${jobsInput.substring(0, 100)}${jobsInput.length > 100 ? '...' : ''}`);
    }
    validateJobs(jobs);
    return { webhookUrl, jobs };
}

function buildVariableFields(variablesOutputs) {
    const fields = [];
    for (const key of Object.keys(variablesOutputs)) {
      if (key.match(/^(DEPLOY|SKIP|UPDATE)_/)) {
        if (variablesOutputs[key] === '1') {
          fields.push({
            "type": "plain_text",
            "emoji": true,
            "text": `:heavy_check_mark: ${key}`
          })
        }
      }
    }
    return fields;
}

function buildHeaderAttachment(variablesOutputs, variableFields) {
    const blocks = [
      {
        "type": "section",
        "text": {
          "type": "mrkdwn",
          "text": `*<${githubEnv('GITHUB_SERVER_URL')}/${githubEnv('GITHUB_REPOSITORY')}/actions/runs/${githubEnv('GITHUB_RUN_ID')}|Build #${githubEnv('GITHUB_RUN_NUMBER')} (${githubEnv('GITHUB_SHA')}) ${githubEnv('GITHUB_EVENT_NAME')}>*`
        }
      },
      {
        "type": "context",
        "elements": [
          {
            "type": "mrkdwn",
            "text": `${githubEnv('GITHUB_REPOSITORY')}@${githubEnv('GITHUB_REF')} by *${githubEnv('GITHUB_ACTOR')}*`
          }
        ]
      },
      {
        "type": "context",
        "elements": [
          {
            "type": "plain_text",
            "text": `${variablesOutputs.COMMIT_MESSAGE || ''}`
          }
        ]
      },
      {
        "type": "divider"
      }
    ];

    if (variableFields.length > 0) {
      blocks.push({
        "type": "section",
          "fields": variableFields
      });
      blocks.push({
        "type": "divider"
      });
    }

    return { "color": COLORS.info, "blocks": blocks };
}

function buildJobAttachments(jobs) {
    const attachments = [];
    let color = COLORS.success;
    let fields = [];

    for (const jobName of Object.keys(jobs)) {
      if (jobName === 'variables') {
        continue;
      }

      let emoji = ':question:';
      switch (jobs[jobName].result) {
        case 'success':
          emoji = ':white_check_mark:';
          break;
        case 'failure':
          emoji = ':x:';
          color = COLORS.failure;
          break;
        case 'cancelled':
          emoji = ':hand:'
          color = COLORS.warning;
          break;
        case 'skipped':
          emoji = ':heavy_minus_sign:'
          break;
      }

      fields.push({
        "type": "plain_text",
        'emoji': true,
        "text": `${emoji} ${jobName}`
      });

      if (fields.length >= 2) {
        attachments.push({
          "color": color,
          "blocks": [
            {
              "type": "section",
              "fields": fields
            }
          ]
        });
        fields = [];
        color = COLORS.success;
      }
    }

    if (fields.length > 0) {
      attachments.push({
        "color": color,
        "blocks": [
          {
            "type": "section",
            "fields": fields
          }
        ]
      });
    }

    return attachments;
}

async function sendWebhook(webhookUrl, data) {
    console.log(JSON.stringify(data, undefined, 2));
    const response = await axios.post(webhookUrl, data, { timeout: 30000 });
    console.log(JSON.stringify(response.data, undefined, 2));
}

async function run() {
    const { webhookUrl, jobs } = parseInputs();
    const variablesOutputs = jobs?.variables?.outputs || {};
    const variableFields = buildVariableFields(variablesOutputs);
    const headerAttachment = buildHeaderAttachment(variablesOutputs, variableFields);
    const jobAttachments = buildJobAttachments(jobs);
    const data = { "attachments": [headerAttachment, ...jobAttachments] };
    await sendWebhook(webhookUrl, data);
}

// Surface full failure context before failing the step. The default
// `core.setFailed(error.message)` dropped the stack and, for axios errors,
// the Slack API response body (e.g. "invalid_payload") - the most useful
// part for debugging a 4xx.
function reportError(error) {
    if (error && error.stack) {
        core.error(error.stack);
    }
    const responseData = error && error.response && error.response.data;
    if (responseData !== undefined) {
        core.error(`Response body: ${JSON.stringify(responseData)}`);
    }
    core.setFailed(error && error.message ? error.message : String(error));
}

module.exports = { run, COLORS, validateJobs, githubEnv, reportError };

/* istanbul ignore next */
if (require.main === module) {
    run().catch(reportError);
}
