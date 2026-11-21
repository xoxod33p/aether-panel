package service

import (
	"encoding/json"
	"fmt"
	"gorm.io/gorm"
	"time"
	"aether-vpn/database"
	"aether-vpn/database/model"
	"aether-vpn/util/common"
	"aether-vpn/xray"
)

type InboundService struct {
}

func (s *InboundService) GetInbounds(userId int) ([]*model.Inbound, error) {
	db := database.GetDB()
	var inbounds []*model.Inbound
	err := db.Model(model.Inbound{}).Where("user_id = ?", userId).Find(&inbounds).Error
	if err != nil && err != gorm.ErrRecordNotFound {
		return nil, err
	}
	return inbounds, nil
}

func (s *InboundService) GetAllInbounds() ([]*model.Inbound, error) {
	db := database.GetDB()
	var inbounds []*model.Inbound
	err := db.Model(model.Inbound{}).Find(&inbounds).Error
	if err != nil && err != gorm.ErrRecordNotFound {
		return nil, err
	}
	return inbounds, nil
}

func (s *InboundService) checkPortExist(port int, ignoreId int) (bool, error) {
	db := database.GetDB()
	db = db.Model(model.Inbound{}).Where("port = ?", port)
	if ignoreId > 0 {
		db = db.Where("id != ?", ignoreId)
	}
	var count int64
	err := db.Count(&count).Error
	if err != nil {
		return false, err
	}
	return count > 0, nil
}

func (s *InboundService) AddInbound(inbound *model.Inbound) error {
	exist, err := s.checkPortExist(inbound.Port, 0)
	if err != nil {
		return err
	}
	if exist {
		return common.NewError("Port already exists:", inbound.Port)
	}
	db := database.GetDB()
	return db.Save(inbound).Error
}

func (s *InboundService) AddInbounds(inbounds []*model.Inbound) error {
	for _, inbound := range inbounds {
		exist, err := s.checkPortExist(inbound.Port, 0)
		if err != nil {
			return err
		}
		if exist {
			return common.NewError("Port already exists:", inbound.Port)
		}
	}

	db := database.GetDB()
	tx := db.Begin()
	var err error
	defer func() {
		if err == nil {
			tx.Commit()
		} else {
			tx.Rollback()
		}
	}()

	for _, inbound := range inbounds {
		err = tx.Save(inbound).Error
		if err != nil {
			return err
		}
	}

	return nil
}

func (s *InboundService) DelInbound(id int) error {
	db := database.GetDB()
	return db.Delete(model.Inbound{}, id).Error
}

func (s *InboundService) GetInbound(id int) (*model.Inbound, error) {
	db := database.GetDB()
	inbound := &model.Inbound{}
	err := db.Model(model.Inbound{}).First(inbound, id).Error
	if err != nil {
		return nil, err
	}
	return inbound, nil
}

func (s *InboundService) UpdateInbound(inbound *model.Inbound) error {
	exist, err := s.checkPortExist(inbound.Port, inbound.Id)
	if err != nil {
		return err
	}
	if exist {
		return common.NewError("Port already exists:", inbound.Port)
	}

	oldInbound, err := s.GetInbound(inbound.Id)
	if err != nil {
		return err
	}
	oldInbound.Up = inbound.Up
	oldInbound.Down = inbound.Down
	oldInbound.Total = inbound.Total
	oldInbound.Remark = inbound.Remark
	oldInbound.Enable = inbound.Enable
	oldInbound.ExpiryTime = inbound.ExpiryTime
	oldInbound.Listen = inbound.Listen
	oldInbound.Port = inbound.Port
	oldInbound.Protocol = inbound.Protocol
	oldInbound.Settings = inbound.Settings
	oldInbound.StreamSettings = inbound.StreamSettings
	oldInbound.Sniffing = inbound.Sniffing
	oldInbound.Tag = fmt.Sprintf("inbound-%v", inbound.Port)

	db := database.GetDB()
	return db.Save(oldInbound).Error
}

func (s *InboundService) AddTraffic(traffics []*xray.Traffic) (err error) {
	if len(traffics) == 0 {
		return nil
	}
	db := database.GetDB()
	tx := db.Begin()
	defer func() {
		if err != nil {
			tx.Rollback()
		} else {
			tx.Commit()
		}
	}()

	userTraffics := make(map[string]*xray.Traffic)
	for _, traffic := range traffics {
		if traffic.IsInbound {
			err = tx.Model(model.Inbound{}).Where("tag = ?", traffic.Tag).
				UpdateColumn("up", gorm.Expr("up + ?", traffic.Up)).
				UpdateColumn("down", gorm.Expr("down + ?", traffic.Down)).
				Error
			if err != nil {
				return
			}
		} else if traffic.IsUser {
			userTraffics[traffic.Tag] = traffic
		}
	}

	if len(userTraffics) > 0 {
		var inbounds []*model.Inbound
		err = tx.Model(model.Inbound{}).Find(&inbounds).Error
		if err != nil {
			return
		}
		for _, inbound := range inbounds {
			if inbound.Settings == "" {
				continue
			}
			var settingsMap map[string]interface{}
			if err := json.Unmarshal([]byte(inbound.Settings), &settingsMap); err != nil {
				continue
			}
			clientsRaw, ok := settingsMap["clients"]
			if !ok {
				continue
			}
			clients, ok := clientsRaw.([]interface{})
			if !ok || len(clients) == 0 {
				continue
			}
			modified := false
			for _, c := range clients {
				clientMap, ok := c.(map[string]interface{})
				if !ok {
					continue
				}
				email, _ := clientMap["email"].(string)
				id, _ := clientMap["id"].(string)
				var t *xray.Traffic
				if email != "" {
					t = userTraffics[email]
				}
				if t == nil && id != "" {
					t = userTraffics[id]
				}
				if t != nil {
					var curUp, curDown int64
					if u, ok := clientMap["up"].(float64); ok {
						curUp = int64(u)
					}
					if d, ok := clientMap["down"].(float64); ok {
						curDown = int64(d)
					}
					clientMap["up"] = curUp + t.Up
					clientMap["down"] = curDown + t.Down
					modified = true
				}
			}
			if modified {
				settingsMap["clients"] = clients
				newSettings, err := json.Marshal(settingsMap)
				if err == nil {
					err = tx.Model(model.Inbound{}).Where("id = ?", inbound.Id).
						Update("settings", string(newSettings)).Error
					if err != nil {
						return err
					}
				}
			}
		}
	}
	return
}

func (s *InboundService) DisableInvalidInbounds() (int64, error) {
	db := database.GetDB()
	now := time.Now().Unix() * 1000
	result := db.Model(model.Inbound{}).
		Where("((total > 0 and up + down >= total) or (expiry_time > 0 and expiry_time <= ?)) and enable = ?", now, true).
		Update("enable", false)
	err := result.Error
	count := result.RowsAffected
	if err != nil {
		return count, err
	}

	// Check per-client limits across inbounds
	var inbounds []*model.Inbound
	err = db.Model(model.Inbound{}).Where("enable = ?", true).Find(&inbounds).Error
	if err != nil {
		return count, err
	}
	for _, inbound := range inbounds {
		if inbound.Settings == "" {
			continue
		}
		var settingsMap map[string]interface{}
		if err := json.Unmarshal([]byte(inbound.Settings), &settingsMap); err != nil {
			continue
		}
		clientsRaw, ok := settingsMap["clients"]
		if !ok {
			continue
		}
		clients, ok := clientsRaw.([]interface{})
		if !ok {
			continue
		}
		clientChanged := false
		for _, c := range clients {
			clientMap, ok := c.(map[string]interface{})
			if !ok {
				continue
			}
			enable, exists := clientMap["enable"]
			if exists {
				if enableBool, ok := enable.(bool); ok && !enableBool {
					continue
				}
			}
			// Check expiry
			if exp, exists := clientMap["expiryTime"]; exists {
				var expTime int64
				switch v := exp.(type) {
				case float64:
					expTime = int64(v)
				case int64:
					expTime = v
				}
				if expTime > 0 && expTime <= now {
					clientMap["enable"] = false
					clientChanged = true
				}
			}
			// Check totalGB
			if totalGBVal, exists := clientMap["totalGB"]; exists {
				var totalGB float64
				switch v := totalGBVal.(type) {
				case float64:
					totalGB = v
				case int:
					totalGB = float64(v)
				case int64:
					totalGB = float64(v)
				}
				if totalGB > 0 {
					var up, down int64
					if u, ok := clientMap["up"].(float64); ok {
						up = int64(u)
					}
					if d, ok := clientMap["down"].(float64); ok {
						down = int64(d)
					}
					limitBytes := int64(totalGB * 1073741824)
					if up+down >= limitBytes {
						clientMap["enable"] = false
						clientChanged = true
					}
				}
			}
		}
		if clientChanged {
			settingsMap["clients"] = clients
			newSettings, err := json.Marshal(settingsMap)
			if err == nil {
				db.Model(model.Inbound{}).Where("id = ?", inbound.Id).Update("settings", string(newSettings))
				count++
			}
		}
	}

	return count, nil
}
