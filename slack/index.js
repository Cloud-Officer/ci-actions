const core = require('@actions/core');
const axios = require("axios");

const COLORS = {
    info: '#439FE0',
    success: '#5cb589',
    failure: '#d5001a',
    warning: '#f8c753'
};

function parseInputs() {
    const webhookUrl = core.getInput('webhook-url');
    const jobsInput = core.getInput('jobs');
    let jobs;
    try {
        jobs = JSON.parse(jobsInput);
    } catch (parseError) {
        throw new Error(`Failed to parse 'jobs' input as JSON: ${parseError.message}. Input was: ${jobsInput.substring(0, 100)}${jobsInput.length > 100 ? '...' : ''}`);
    }
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
          "text": `*<${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}|Build #${process.env.GITHUB_RUN_NUMBER} (${process.env.GITHUB_SHA}) ${process.env.GITHUB_EVENT_NAME}>*`
        }
      },
      {
        "type": "context",
        "elements": [
          {
            "type": "mrkdwn",
            "text": `${process.env.GITHUB_REPOSITORY}@${process.env.GITHUB_REF} by *${process.env.GITHUB_ACTOR}*`
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

module.exports = { run, COLORS };

/* istanbul ignore next */
if (require.main === module) {
    run().catch((error) => {
        core.setFailed(error.message);
    });
}
