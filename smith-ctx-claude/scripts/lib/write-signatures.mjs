export const CONTENT = "content";
export const TARGET = "target";
export const REFERENCE = "reference";
export const STRUCTURAL = "structural";
export const URL_REFERENCE = "reference when a URL";
export const ANY_KEY = "*";
export const SCALAR = "$value";

const NOTION = "mcp__plugin_Notion_notion__notion-";
const ATLASSIAN = "mcp__plugin_atlassian_atlassian__";
const SLACK = "mcp__plugin_slack_slack__slack_";

const NOTION_PROPERTIES = {
  [ANY_KEY]: { [SCALAR]: CONTENT, type: STRUCTURAL, file_upload: REFERENCE },
};
const NOTION_PARENT = {
  [SCALAR]: TARGET,
  type: STRUCTURAL,
  page_id: TARGET,
  database_id: TARGET,
  data_source_id: TARGET,
  teamspace_id: TARGET,
};
const CONFLUENCE_BODY = { format: STRUCTURAL, value: URL_REFERENCE, context: STRUCTURAL };
const INLINE_FILE_FIELDS = {
  inlineFileCollection: REFERENCE,
  inlineFileId: REFERENCE,
  inlineFileName: REFERENCE,
};

export const WRITE_SIGNATURES = {
  [`${NOTION}update-page`]: {
    page_id: TARGET,
    command: CONTENT,
    allow_async: STRUCTURAL,
    allow_deleting_content: CONTENT,
    content: CONTENT,
    content_updates: CONTENT,
    cover: REFERENCE,
    icon: URL_REFERENCE,
    instructions_version: STRUCTURAL,
    is_skill: CONTENT,
    new_str: CONTENT,
    position: TARGET,
    properties: NOTION_PROPERTIES,
    template_id: REFERENCE,
    verification_expiry_days: CONTENT,
    verification_status: CONTENT,
  },
  [`${NOTION}create-pages`]: {
    parent: NOTION_PARENT,
    allow_async: STRUCTURAL,
    creation_mode: CONTENT,
    instructions_version: STRUCTURAL,
    pages: {
      content: CONTENT,
      cover: REFERENCE,
      icon: URL_REFERENCE,
      is_skill: CONTENT,
      preserve_internal_links: STRUCTURAL,
      properties: NOTION_PROPERTIES,
      template_id: REFERENCE,
    },
  },
  [`${NOTION}create-comment`]: {
    page_id: TARGET,
    discussion_id: TARGET,
    reply_to_comment_id: TARGET,
    instructions_version: STRUCTURAL,
    markdown: CONTENT,
    rich_text: CONTENT,
    selection_with_ellipsis: TARGET,
  },
  [`${NOTION}update-comment`]: {
    comment_id: TARGET,
    instructions_version: STRUCTURAL,
    markdown: CONTENT,
  },
  [`${ATLASSIAN}addOrEditJiraIssueComment`]: {
    cloudId: STRUCTURAL,
    issueIdOrKey: TARGET,
    commentId: TARGET,
    commentBody: CONTENT,
    commentVisibility: CONTENT,
    contentFormat: STRUCTURAL,
    jsmCommentType: CONTENT,
    responseContentFormat: STRUCTURAL,
    ...INLINE_FILE_FIELDS,
  },
  [`${ATLASSIAN}editJiraIssue`]: {
    cloudId: STRUCTURAL,
    issueIdOrKey: TARGET,
    actionSource: STRUCTURAL,
    additional_fields: CONTENT,
    contentFormat: STRUCTURAL,
    fields: CONTENT,
    rankAfterIssue: CONTENT,
    rankBeforeIssue: CONTENT,
    rankCustomFieldId: STRUCTURAL,
    responseContentFormat: STRUCTURAL,
    ...INLINE_FILE_FIELDS,
  },
  [`${ATLASSIAN}createJiraIssue`]: {
    cloudId: STRUCTURAL,
    projectKey: TARGET,
    summary: CONTENT,
    issueType: CONTENT,
    description: CONTENT,
    contentFormat: STRUCTURAL,
    additional_fields: CONTENT,
    assignToSprint: CONTENT,
    assignee: CONTENT,
    labels: CONTENT,
    parent: CONTENT,
    priority: CONTENT,
  },
  [`${ATLASSIAN}transitionJiraIssue`]: {
    cloudId: STRUCTURAL,
    issueIdOrKey: TARGET,
    actionSource: STRUCTURAL,
    assignToBacklog: CONTENT,
    boardId: CONTENT,
    fields: CONTENT,
    historyMetadata: CONTENT,
    sprintId: CONTENT,
    transitionId: CONTENT,
    transitionName: CONTENT,
    update: CONTENT,
  },
  [`${ATLASSIAN}createConfluenceContent`]: {
    cloudId: STRUCTURAL,
    parent: TARGET,
    contentType: CONTENT,
    title: CONTENT,
    body: CONFLUENCE_BODY,
    contentWidth: STRUCTURAL,
    draft: CONTENT,
    private: CONTENT,
  },
  [`${ATLASSIAN}updateConfluenceContent`]: {
    cloudId: STRUCTURAL,
    contentId: TARGET,
    contentUrl: TARGET,
    body: CONFLUENCE_BODY,
    edits: CONTENT,
    title: CONTENT,
    versionMessage: CONTENT,
    ownerId: CONTENT,
    draft: CONTENT,
    contentWidth: STRUCTURAL,
    dryRun: STRUCTURAL,
    minorEdit: STRUCTURAL,
    snapshotToken: STRUCTURAL,
  },
  [`${SLACK}create_canvas`]: {
    title: CONTENT,
    content: CONTENT,
  },
  [`${SLACK}update_canvas`]: {
    canvas_id: TARGET,
    action: CONTENT,
    content: CONTENT,
    section_id: TARGET,
    sections: { content: CONTENT, edit_type: CONTENT, section_id: TARGET },
  },
  [`${SLACK}schedule_message`]: {
    channel_id: TARGET,
    thread_ts: TARGET,
    message: CONTENT,
    post_at: CONTENT,
    reply_broadcast: CONTENT,
  },
};
