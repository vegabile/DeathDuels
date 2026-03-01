export type KnifeSchema = {
	id: string,
	name: string,
	equipped: boolean,
}

export type GunSchema = {
	id: string,
	name: string,
	equipped: boolean,
}

export type DataSchema = {
	Coin: number,
	Knives: { KnifeSchema },
	Guns: { GunSchema },
}

export type OperationSuccessReturnValue = {
	successful : boolean,
	errorMessage : string?,
}

return {}
