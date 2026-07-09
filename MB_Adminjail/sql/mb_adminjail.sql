CREATE TABLE IF NOT EXISTS `mb_mb_adminjail` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `identifier` VARCHAR(100) NOT NULL,
  `name` VARCHAR(80) NOT NULL,
  `reason` TEXT NOT NULL,
  `time_left` INT NOT NULL DEFAULT 0 COMMENT 'Remaining jail time in seconds',
  `jailed_by` VARCHAR(80) NOT NULL,
  `jailed_by_identifier` VARCHAR(100) DEFAULT NULL,
  `jailed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `release_at` INT DEFAULT NULL COMMENT 'Unix timestamp used when Config.TimerMode = realtime',
  `status` VARCHAR(20) NOT NULL DEFAULT 'active',
  `released_by` VARCHAR(80) DEFAULT NULL,
  `released_at` TIMESTAMP NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_identifier_status` (`identifier`, `status`),
  KEY `idx_status` (`status`),
  KEY `idx_jailed_at` (`jailed_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
