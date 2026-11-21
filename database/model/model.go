package model

import (
	"encoding/json"
	"fmt"
	"time"
	"aether-vpn/util/json_util"
	"aether-vpn/xray"
)

type Protocol string

const (
	VMess       Protocol = "vmess"
	VLESS       Protocol = "vless"
	Dokodemo    Protocol = "Dokodemo-door"
	Http        Protocol = "http"
	Trojan      Protocol = "trojan"
	Shadowsocks Protocol = "shadowsocks"
)

type User struct {
	Id       int    `json:"id" gorm:"primaryKey;autoIncrement"`
	Username string `json:"username"`
	Password string `json:"password"`
}

type Inbound struct {
	Id         int    `json:"id" form:"id" gorm:"primaryKey;autoIncrement"`
	UserId     int    `json:"-"`
	Up         int64  `json:"up" form:"up"`
	Down       int64  `json:"down" form:"down"`
	Total      int64  `json:"total" form:"total"`
	Remark     string `json:"remark" form:"remark"`
	Enable     bool   `json:"enable" form:"enable"`
	ExpiryTime int64  `json:"expiryTime" form:"expiryTime"`

	// config part
	Listen         string   `json:"listen" form:"listen"`
	Port           int      `json:"port" form:"port" gorm:"unique"`
	Protocol       Protocol `json:"protocol" form:"protocol"`
	Settings       string   `json:"settings" form:"settings"`
	StreamSettings string   `json:"streamSettings" form:"streamSettings"`
	Tag            string   `json:"tag" form:"tag" gorm:"unique"`
	Sniffing       string   `json:"sniffing" form:"sniffing"`
}

func (i *Inbound) GenActiveSettings() string {
	if i.Settings == "" {
		return "{}"
	}
	var settingsMap map[string]interface{}
	err := json.Unmarshal([]byte(i.Settings), &settingsMap)
	if err != nil {
		return i.Settings
	}
	clientsRaw, ok := settingsMap["clients"]
	if !ok {
		return i.Settings
	}
	clients, ok := clientsRaw.([]interface{})
	if !ok || len(clients) == 0 {
		return i.Settings
	}

	now := time.Now().Unix() * 1000
	activeClients := make([]interface{}, 0, len(clients))

	for idx, c := range clients {
		clientMap, ok := c.(map[string]interface{})
		if !ok {
			activeClients = append(activeClients, c)
			continue
		}

		// Check if client is disabled
		if enable, exists := clientMap["enable"]; exists {
			if enableBool, ok := enable.(bool); ok && !enableBool {
				continue
			}
		}

		// Check client expiry
		if exp, exists := clientMap["expiryTime"]; exists {
			var expTime int64
			switch v := exp.(type) {
			case float64:
				expTime = int64(v)
			case int64:
				expTime = v
			}
			if expTime > 0 && expTime <= now {
				continue
			}
		}

		// Check client totalGB bandwidth limit
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
					continue
				}
			}
		}

		// Ensure client has email tag so Xray generates user stats
		email, exists := clientMap["email"]
		if !exists || email == nil || email == "" {
			clientMap["email"] = fmt.Sprintf("%v-u%v", i.Tag, idx+1)
		}

		activeClients = append(activeClients, clientMap)
	}

	settingsMap["clients"] = activeClients
	res, err := json.Marshal(settingsMap)
	if err != nil {
		return i.Settings
	}
	return string(res)
}

func (i *Inbound) GenXrayInboundConfig() *xray.InboundConfig {
	listen := i.Listen
	if listen != "" {
		listen = fmt.Sprintf("\"%v\"", listen)
	}
	return &xray.InboundConfig{
		Listen:         json_util.RawMessage(listen),
		Port:           i.Port,
		Protocol:       string(i.Protocol),
		Settings:       json_util.RawMessage(i.GenActiveSettings()),
		StreamSettings: json_util.RawMessage(i.StreamSettings),
		Tag:            i.Tag,
		Sniffing:       json_util.RawMessage(i.Sniffing),
	}
}

type Setting struct {
	Id    int    `json:"id" form:"id" gorm:"primaryKey;autoIncrement"`
	Key   string `json:"key" form:"key"`
	Value string `json:"value" form:"value"`
}
