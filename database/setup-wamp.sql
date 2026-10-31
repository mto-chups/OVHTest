-- À exécuter une seule fois dans phpMyAdmin ou la console MySQL de WAMP.
CREATE DATABASE IF NOT EXISTS deployment_test
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

-- Utile lorsque Node tourne dans Docker : évite d'exposer le compte root.
CREATE USER IF NOT EXISTS 'deployment_app'@'%' IDENTIFIED BY 'change-me-local';
GRANT ALL PRIVILEGES ON deployment_test.* TO 'deployment_app'@'%';
FLUSH PRIVILEGES;
