CREATE TABLE IF NOT EXISTS `rs_camp` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `owner_identifier` varchar(255) DEFAULT NULL,
  `owner_charid` int(11) DEFAULT NULL,
  `x` double DEFAULT NULL,
  `y` double DEFAULT NULL,
  `z` double DEFAULT NULL,
  `rot_x` double DEFAULT NULL,
  `rot_y` double DEFAULT NULL,
  `rot_z` double DEFAULT NULL,
  `item_name` varchar(50) DEFAULT NULL,
  `item_model` varchar(100) DEFAULT NULL,
  `shared_with` text DEFAULT '[]',
  PRIMARY KEY (`id`)
);
