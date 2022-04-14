const core = require('@actions/core');
const axios = require("axios");

try {
    const webhook_url = core.getInput('webhook-url');
    const jobs = JSON.parse(core.getInput('jobs'));
    let fields, block;

    fields = [];
    for (var i in jobs.variables.outputs) {
      if (i.match(/^(DEPLOY|SKIP|UPDATE)_/)) {
        if (jobs.variables.outputs[i] == '1') {
          fields.push({
            "type": "plain_text",
            "emoji": true,
            "text": `:heavy_check_mark: ${i}`
          })
        }
      }
    }

    let data = {"attachments": [
      {
        "color": "#439FE0",
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

    let color = '#5cb589';
    fields = [];
    for (var i in jobs) {
      if (i == 'variables') {
        continue;
      }

      var emoji = ':question:';
      switch (jobs[i].result) {
        case 'success':
          emoji = ':white_check_mark:';
          break;
        case 'failure':
          emoji = ':x:';
          color = '#d5001a';
          break;
        case 'cancelled':
          emoji = ':hand:'
          color = '#f8c753';
          break;
        case 'skipped':
          emoji = ':heavy_minus_sign:'
          break;
      }

      fields.push({
        "type": "plain_text",
        'emoji': true,
        "text": `${emoji} ${i}`
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
        color = '#5cb589';
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

    let res = axios.post(webhook_url, data);
    console.log(JSON.stringify(res, undefined, 2));
} catch (error) {
    core.setFailed(error.message);
}
