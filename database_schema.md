# Database Schema

## Tables

### roles
| Column      | Type    | Constraints                   | Description |
|-------------|---------|-------------------------------|-------------|
| role_id     | INTEGER | Primary Key                   |             |
| role_name   | TEXT    | Unique, Not Null              |             |
| description | TEXT    |                               |             |

### conversations
| Column           | Type    | Constraints                                           | Description                                     |
|------------------|---------|-------------------------------------------------------|-------------------------------------------------|
| conversation_id  | TEXT    | Primary Key                                           |                                                 |
| title            | TEXT    |                                                       |                                                 |
| create_time      | REAL    |                                                       |                                                 |
| update_time      | REAL    |                                                       |                                                 |
| current_node_id  | TEXT    |                                                       |                                                 |
| message_count    | INTEGER | Default 0                                             |                                                 |
| plugin_ids       | TEXT    |                                                       |                                                 |
| gizmo_id         | TEXT    |                                                       |                                                 |
| is_archived      | INTEGER | Default 0                                             |                                                 |
| extra_json       | TEXT    |                                                       |                                                 |
| created_date     | TEXT    | Generated Always As date(create_time, 'unixepoch') Stored | Date of creation (YYYY-MM-DD)                   |
| updated_date     | TEXT    | Generated Always As date(update_time, 'unixepoch') Stored | Date of last update (YYYY-MM-DD)                |

### nodes
| Column           | Type    | Constraints                                                  | Description |
|------------------|---------|--------------------------------------------------------------|-------------|
| node_id          | TEXT    | Primary Key                                                  |             |
| conversation_id  | TEXT    | Not Null, Foreign Key references conversations(conversation_id) ON DELETE CASCADE |             |
| parent_node_id   | TEXT    | Foreign Key references nodes(node_id) ON DELETE SET NULL     |             |
| is_visible       | INTEGER | Default 1                                                    |             |
| depth_level      | INTEGER | Default 0                                                    |             |
| child_count      | INTEGER | Default 0                                                    |             |
| extra_json       | TEXT    |                                                              |             |

### messages
| Column           | Type    | Constraints                                                                                                | Description                                                           |
|------------------|---------|------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------|
| message_id       | TEXT    | Primary Key                                                                                                |                                                                       |
| node_id          | TEXT    | Not Null, Foreign Key references nodes(node_id) ON DELETE CASCADE                                          |                                                                       |
| conversation_id  | TEXT    | Not Null, Foreign Key references conversations(conversation_id) ON DELETE CASCADE                            |                                                                       |
| role_id          | INTEGER | Foreign Key references roles(role_id)                                                                        |                                                                       |
| author_name      | TEXT    |                                                                                                            |                                                                       |
| create_time      | REAL    |                                                                                                            |                                                                       |
| status           | TEXT    |                                                                                                            |                                                                       |
| end_turn         | INTEGER | Default 0                                                                                                  |                                                                       |
| weight           | REAL    | Default 1.0                                                                                                |                                                                       |
| recipient        | TEXT    |                                                                                                            |                                                                       |
| content_type     | TEXT    |                                                                                                            |                                                                       |
| text_content     | TEXT    |                                                                                                            |                                                                       |
| content_json     | TEXT    |                                                                                                            |                                                                       |
| metadata_json    | TEXT    |                                                                                                            |                                                                       |
| extra_json       | TEXT    |                                                                                                            |                                                                       |
| created_date     | TEXT    | Generated Always As date(create_time, 'unixepoch') Stored                                                  | Date of creation (YYYY-MM-DD)                                         |
| word_count       | INTEGER | Generated Always As CASE WHEN text_content IS NOT NULL AND length(text_content)>0 THEN length(text_content) - length(replace(text_content, ' ', '')) + 1 ELSE 0 END Stored | Word count of the `text_content`                                      |

### attachments
| Column         | Type    | Constraints                                                        | Description |
|----------------|---------|--------------------------------------------------------------------|-------------|
| attachment_id  | TEXT    | Primary Key                                                        |             |
| message_id     | TEXT    | Not Null, Foreign Key references messages(message_id) ON DELETE CASCADE |             |
| file_name      | TEXT    |                                                                    |             |
| file_size      | INTEGER |                                                                    |             |
| mime_type      | TEXT    |                                                                    |             |
| width          | INTEGER |                                                                    |             |
| height         | INTEGER |                                                                    |             |
| asset_pointer  | TEXT    |                                                                    |             |
| extra_json     | TEXT    |                                                                    |             |

### citations
| Column         | Type    | Constraints                                                        | Description |
|----------------|---------|--------------------------------------------------------------------|-------------|
| citation_id    | INTEGER | Primary Key Auto-Increment                                         |             |
| message_id     | TEXT    | Not Null, Foreign Key references messages(message_id) ON DELETE CASCADE |             |
| url            | TEXT    |                                                                    |             |
| title          | TEXT    |                                                                    |             |
| snippet        | TEXT    |                                                                    |             |
| citation_index | INTEGER |                                                                    |             |
| extra_json     | TEXT    |                                                                    |             |

### tool_calls
| Column          | Type    | Constraints                                                        | Description |
|-----------------|---------|--------------------------------------------------------------------|-------------|
| tool_call_id    | TEXT    | Primary Key                                                        |             |
| message_id      | TEXT    | Not Null, Foreign Key references messages(message_id) ON DELETE CASCADE |             |
| tool_name       | TEXT    |                                                                    |             |
| arguments_json  | TEXT    |                                                                    |             |
| result_json     | TEXT    |                                                                    |             |
| status          | TEXT    |                                                                    |             |
| error_message   | TEXT    |                                                                    |             |

## Indexes

| Index Name     | Table    | Columns         |
|----------------|----------|-----------------|
| idx_msg_conv   | messages | conversation_id |
| idx_msg_role   | messages | role_id         |
| idx_nodes_conv | nodes    | conversation_id |

## View

### conversation_stats
This view provides aggregated statistics for each conversation.

**Selected Columns from `conversations` table:**
*   `conversation_id`
*   `title`
*   `created_date`

**Calculated Fields:**
*   `total_messages`: Total count of messages for the conversation (from `messages` table).
*   `user_messages`: Total count of messages where `role_name` is 'user' (from `messages` joined with `roles`).
*   `assistant_messages`: Total count of messages where `role_name` is 'assistant' (from `messages` joined with `roles`).
*   `system_messages`: Total count of messages where `role_name` is 'system' (from `messages` joined with `roles`).
*   `tool_messages`: Total count of messages where `role_name` is 'tool' (from `messages` joined with `roles`).
*   `total_words`: Total sum of `word_count` for all messages in the conversation (from `messages` table).
*   `attachments`: Total count of attachments for the conversation (from `attachments` table).
*   `citations`: Total count of citations for the conversation (from `citations` table).

**Joins:**
*   `conversations` LEFT JOIN `messages` ON `conversations`.`conversation_id` = `messages`.`conversation_id`
*   `messages` LEFT JOIN `roles` ON `messages`.`role_id` = `roles`.`role_id`
*   `messages` LEFT JOIN `attachments` ON `messages`.`message_id` = `attachments`.`message_id`
*   `messages` LEFT JOIN `citations` ON `messages`.`message_id` = `citations`.`message_id`

**Grouping:**
*   Results are grouped by `conversations`.`conversation_id`.

## Virtual Tables (FTS5 for Full-Text Search)

The following tables are used by SQLite's FTS5 extension to enable full-text searching on the `text_content` column of the `messages` table.

*   **`message_fts`**: The main FTS5 table. It's configured to index `text_content` and stores `message_id` unindexed.
    *   `CREATE VIRTUAL TABLE message_fts USING fts5(text_content, message_id UNINDEXED)`
*   **`message_fts_data`**: Stores the actual indexed data in segments.
*   **`message_fts_idx`**: An index on the terms in the FTS table.
*   **`message_fts_content`**: Provides direct access to the content stored in the FTS table.
*   **`message_fts_docsize`**: Stores the size of each document (row) in the FTS table.
*   **`message_fts_config`**: Stores the configuration of the FTS table.

This setup allows for efficient searching of message text content.
```
