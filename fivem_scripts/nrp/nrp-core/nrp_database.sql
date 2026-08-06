-- NRP Core Database Schema
-- Tabela de jogadores/personagens

CREATE TABLE IF NOT EXISTS `nrp_players` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `identifier` varchar(100) NOT NULL,
  `firstname` varchar(50) NOT NULL,
  `lastname` varchar(50) NOT NULL,
  `nationalid` varchar(50) DEFAULT NULL,
  `dob` date DEFAULT NULL,
  `gender` enum('m', 'f') NOT NULL,
  `cash` int(11) DEFAULT 1000,
  `bank` int(11) DEFAULT 5000,
  `blackmoney` int(11) DEFAULT 0,
  `job` varchar(50) DEFAULT 'unemployed',
  `job_grade` int(11) DEFAULT 0,
  `gang` varchar(50) DEFAULT 'none',
  `gang_grade` int(11) DEFAULT 0,
  `metadata` text DEFAULT NULL,
  `appearance` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `identifier` (`identifier`),
  KEY `firstname_lastname` (`firstname`, `lastname`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Índices para otimizar buscas
CREATE INDEX IF NOT EXISTS `idx_identifier` ON `nrp_players` (`identifier`);
CREATE INDEX IF NOT EXISTS `idx_names` ON `nrp_players` (`firstname`, `lastname`);
