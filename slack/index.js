const core = require('@actions/core');
const axios = require("axios");

const COLORS = {
    info: '#439FE0',
    success: '#5cb589',
    failure: '#d5001a',
    warning: '#f8c753'
};

try {
    const webhook_url = core.getInput('webhook-url');
    const jobsInput = core.getInput('jobs');
    let jobs;
    try {
        jobs = JSON.parse(jobsInput);
    } catch (parseError) {
        throw new Error(`Failed to parse 'jobs' input as JSON: ${parseError.message}. Input was: ${jobsInput.substring(0, 100)}${jobsInput.length > 100 ? '...' : ''}`);
    }
    let fields;

    fields = [];
    for (const key of Object.keys(jobs.variables.outputs)) {
      if (key.match(/^(DEPLOY|SKIP|UPDATE)_/)) {
        if (jobs.variables.outputs[key] == '1') {
          fields.push({
            "type": "plain_text",
            "emoji": true,
            "text": `:heavy_check_mark: ${key}`
          })
        }
      }
    }

    let data = {"attachments": [
      {
        "color": COLORS.info,
        "blocks": [
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
                "text": `${jobs.variables.outputs.COMMIT_MESSAGE}`
              }
            ]
          },
          {
            "type": "divider"
          }
        ]
      }
    ]};

    if (fields.length > 0) {
      data.attachments[0].blocks.push({
        "type": "section",
          "fields": fields
      });
      data.attachments[0].blocks.push({
        "type": "divider"
      });
    }

    let color = COLORS.success;
    fields = [];
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
        data.attachments.push({
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
      data.attachments.push({
        "color": color,
        "blocks": [
          {
            "type": "section",
            "fields": fields
          }
        ]
      });
    }
    console.log(JSON.stringify(data, undefined, 2));

    axios.post(webhook_url, data)
        .then((response) => {
          console.log(JSON.stringify(response.data, undefined, 2));
        })
        .catch((error) => {
          console.error('Error', error.message);
          core.setFailed(error.message);
        })
} catch (error) {
    core.setFailed(error.message);
}
