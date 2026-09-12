/// <reference types="@raycast/api">

/* 🚧 🚧 🚧
 * This file is auto-generated from the extension's manifest.
 * Do not modify manually. Instead, update the `package.json` file.
 * 🚧 🚧 🚧 */

/* eslint-disable @typescript-eslint/ban-types */

type ExtensionPreferences = {
  /** Default Project Directory - Working directory for new chats. Leave empty to pick per chat. */
  "defaultDirectory"?: string
}

/** Preferences accessible in all the extension's commands */
declare type Preferences = ExtensionPreferences

declare namespace Preferences {
  /** Preferences accessible in the `chat` command */
  export type Chat = ExtensionPreferences & {}
  /** Preferences accessible in the `sessions` command */
  export type Sessions = ExtensionPreferences & {}
}

declare namespace Arguments {
  /** Arguments passed to the `chat` command */
  export type Chat = {}
  /** Arguments passed to the `sessions` command */
  export type Sessions = {}
}

